import SwiftUI

/// First-launch sheet. Two ways in:
///  - **Invite code** (the path for friends & family): a short code from the
///    developer; AI requests go through the Foob proxy, no Anthropic
///    account needed.
///  - **My own API key** (the developer / power-user path): a Claude key used
///    directly against Anthropic, exactly as before.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    private enum Path: String, CaseIterable, Identifiable {
        case invite = "Invite code"
        case ownKey = "My own API key"
        var id: String { rawValue }
    }

    @State private var path: Path = .invite
    @State private var inviteCode = ""
    @State private var claudeKey = ""
    @State private var usdaKey = ""

    private var canStart: Bool {
        switch path {
        case .invite: return !inviteCode.trimmingCharacters(in: .whitespaces).isEmpty
        case .ownKey: return !claudeKey.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        LuxSheet {
            ScrollView {
                VStack(spacing: 0) {
                    Text("WELCOME")
                        .font(Lux.title(24))
                        .tracking(3)
                        .engravedFill()
                        .padding(.top, 26)

                    LuxNote(
                        "Describe meals in plain English — by voice, Siri, or typing. Foob parses them and looks the macros up for you.",
                        size: 16
                    )
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)

                    LuxSwitcher(
                        options: [(Path.invite, "INVITE CODE"), (Path.ownKey, "MY OWN API KEY")],
                        selection: $path,
                        spacing: 22
                    )
                    .padding(.top, 26)

                    fields
                        .padding(.top, 26)

                    Button("GET STARTED") {
                        save()
                        dismiss()
                    }
                    .buttonStyle(GoldCapsule(enabled: canStart))
                    .disabled(!canStart)
                    .padding(.top, 30)
                }
                .padding(.horizontal, Lux.hPad)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .interactiveDismissDisabled(!canStart)
    }

    @ViewBuilder
    private var fields: some View {
        switch path {
        case .invite:
            VStack(alignment: .leading, spacing: 10) {
                LuxFieldLabel(text: "INVITE CODE")
                LuxUnderlinedField(
                    placeholder: "e.g. MOM-7291",
                    text: $inviteCode,
                    autocapitalization: .characters
                )
                LuxNote("The code you were given by whoever shared Foob with you. That's all you need — AI requests are handled for you.")
            }
        case .ownKey:
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    LuxFieldLabel(text: "CLAUDE API KEY")
                    LuxUnderlinedField(placeholder: "sk-ant-…", text: $claudeKey, secure: true)
                    LuxNote("Create one at console.anthropic.com. Stored in the iOS Keychain.")
                }
                VStack(alignment: .leading, spacing: 10) {
                    LuxFieldLabel(text: "USDA API KEY (OPTIONAL)")
                    LuxUnderlinedField(
                        placeholder: "Leave empty to use DEMO_KEY",
                        text: $usdaKey,
                        secure: true
                    )
                    LuxNote("The free public DEMO_KEY works out of the box but is rate-limited. Get your own free key at api.data.gov when you're ready.")
                }
            }
        }
    }

    private func save() {
        switch path {
        case .invite:
            KeychainService.set(
                inviteCode.trimmingCharacters(in: .whitespaces), for: .proxyInviteCode
            )
        case .ownKey:
            KeychainService.set(claudeKey, for: .claudeAPIKey)
            if !usdaKey.isEmpty {
                KeychainService.set(usdaKey, for: .usdaAPIKey)
            }
        }
    }
}
