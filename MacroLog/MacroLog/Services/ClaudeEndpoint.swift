import Foundation

/// The ONE place that knows how to reach Claude. Every AI call (meal parsing,
/// label scanning, dish estimation) builds its URLRequest here, so the app can
/// speak to either:
///
///  - **The MacroLog proxy** (friends & family): authenticated by a short
///    invite code; the Anthropic key lives on the server (see `server/`),
///    which also meters per-person usage/cost.
///  - **Anthropic directly** (bring your own key): the original path, using
///    the Claude API key from the Keychain.
///
/// An invite code wins when both are configured — the proxy is the intended
/// path for everyone except the developer.
enum ClaudeEndpoint {
    /// The deployed proxy Worker URL. Baked in (rather than typed by each
    /// user) so a friend's entire setup is "enter your invite code". Update
    /// if the Worker is ever redeployed under a different name — a Settings
    /// override can also point at a new URL without rebuilding.
    static let defaultProxyURL = "https://macrolog-proxy.biz-alexnovak.workers.dev"

    /// UserDefaults key for a Settings override of the proxy URL (useful for
    /// testing a new deployment without rebuilding).
    static let proxyURLDefaultsKey = "claude_proxy_url"

    /// How this install reaches Claude. Resolved fresh per request — cheap,
    /// and picks up Settings changes immediately.
    enum Access {
        case proxy(url: URL, inviteCode: String)
        case direct(apiKey: String)
    }

    static var access: Access? {
        resolveAccess(
            inviteCode: KeychainService.get(.proxyInviteCode),
            proxyURLOverride: UserDefaults.standard.string(forKey: proxyURLDefaultsKey),
            apiKey: KeychainService.get(.claudeAPIKey)
        )
    }

    /// True when some way of reaching Claude is configured (gates onboarding).
    static var isConfigured: Bool { access != nil }

    /// Pure resolution logic, separated for tests. Invite code + reachable
    /// proxy URL beats a direct key.
    static func resolveAccess(
        inviteCode: String?, proxyURLOverride: String?, apiKey: String?
    ) -> Access? {
        let urlString = [proxyURLOverride, defaultProxyURL]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        if let inviteCode, !inviteCode.isEmpty,
           let urlString, var url = URL(string: urlString) {
            // Accept the bare Worker origin; the messages path is appended.
            if url.path.isEmpty || url.path == "/" {
                url = url.appendingPathComponent("v1/messages")
            }
            return .proxy(url: url, inviteCode: inviteCode)
        }
        if let apiKey, !apiKey.isEmpty {
            return .direct(apiKey: apiKey)
        }
        return nil
    }

    /// Proxy origin + invite code when the proxy path is active — the same
    /// server also hosts the community food/recipe database (CommunitySync).
    /// Nil for direct-key users: they have no shared server to sync with.
    static var proxyConfig: (base: URL, inviteCode: String)? {
        guard case .proxy(let url, let code) = access else { return nil }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.path = ""
        comps?.query = nil
        guard let base = comps?.url else { return nil }
        return (base, code)
    }

    /// A ready-to-send POST for the Messages API, throwing the shared
    /// missing-key error when nothing is configured. Callers attach their
    /// encoded body.
    static func makeRequest(timeout: TimeInterval) throws -> URLRequest {
        guard let access else { throw MealParsingError.missingAPIKey }

        var request: URLRequest
        switch access {
        case .proxy(let url, let inviteCode):
            request = URLRequest(url: url)
            request.setValue(inviteCode, forHTTPHeaderField: "x-macrolog-user")
        case .direct(let apiKey):
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        return request
    }
}
