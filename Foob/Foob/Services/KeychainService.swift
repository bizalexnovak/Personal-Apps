import Foundation
import Security

/// Thin wrapper over the iOS Keychain for storing API keys.
/// Keys never touch UserDefaults.
enum KeychainService {
    enum Key: String, CaseIterable {
        case claudeAPIKey = "claude_api_key"
        case usdaAPIKey = "usda_api_key"
        /// Invite code for the Foob proxy (friends & family — no Anthropic
        /// account needed; see ClaudeEndpoint).
        case proxyInviteCode = "proxy_invite_code"
        // Optional recipe-search providers (see RecipeSearchService).
        case spoonacularAPIKey = "spoonacular_api_key"
        case edamamAppID = "edamam_app_id"
        case edamamAppKey = "edamam_app_key"
    }

    private static let service = "com.alexnovak.foob.keys"

    @discardableResult
    static func set(_ value: String, for key: Key) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        // Delete any existing item first; SecItemUpdate/Add split isn't worth the complexity here.
        delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    @discardableResult
    static func delete(_ key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    /// USDA FoodData Central accepts the public "DEMO_KEY" with tight rate
    /// limits — good enough until the user registers a free key.
    static var usdaKeyOrDemo: String {
        // Qualified with Self: an unqualified `get(...)` at the start of a
        // computed-property body parses as the `get` accessor keyword.
        Self.get(.usdaAPIKey) ?? "DEMO_KEY"
    }
}
