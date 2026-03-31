import Foundation
import Security

enum KeychainService {
    private static let service = "com.konradmichalik.spark"

    static func save(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete first so a fresh ACL is created with the current code signature.
        // This prevents Keychain prompts after ad-hoc re-signing ("Sign to Run Locally").
        delete(account: account)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)

        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Read Claude Code CLI credentials from Keychain
    static func readClaudeCodeCredentials() -> ClaudeCredentials? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "Claude Code-credentials" as CFString,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else {
            return nil
        }

        let subscriptionType = oauth["subscriptionType"] as? String
        let rateLimitTier = oauth["rateLimitTier"] as? String

        return ClaudeCredentials(
            accessToken: token,
            subscriptionType: subscriptionType,
            rateLimitTier: rateLimitTier
        )
    }

    /// Convenience: read just the token
    static func readClaudeCodeToken() -> String? {
        readClaudeCodeCredentials()?.accessToken
    }
}

struct ClaudeCredentials {
    let accessToken: String
    let subscriptionType: String?
    let rateLimitTier: String?

    var accountTier: AccountTier {
        let plan: String = switch subscriptionType {
        case "pro": "Pro"
        case "max": "Max"
        case "team": "Team"
        default: "Free"
        }

        if let tier = rateLimitTier,
           let range = tier.range(of: #"\d+x"#, options: .regularExpression) {
            return AccountTier(plan: plan, multiplier: String(tier[range]))
        }
        return AccountTier(plan: plan, multiplier: nil)
    }
}

struct AccountTier: Equatable {
    let plan: String
    let multiplier: String?

    var displayName: String {
        if let multiplier { return "\(plan) \(multiplier)" }
        return plan
    }

    static let free = AccountTier(plan: "Free", multiplier: nil)
}
