import Foundation
import os
import Security

enum KeychainService {
    private static let service = "com.konradmichalik.spark"
    private static let log = Logger(subsystem: "com.konradmichalik.spark", category: "auth")

    static func save(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else {
            log.error("save(\(account, privacy: .public)): UTF-8 encoding failed")
            return
        }

        // Delete first so a fresh ACL is created with the current code signature.
        // This prevents Keychain prompts after ad-hoc re-signing ("Sign to Run Locally").
        delete(account: account)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            log.info("save(\(account, privacy: .public)): success")
        } else {
            log.error("save(\(account, privacy: .public)): failed (OSStatus \(status))")
        }
    }

    /// Cache Claude Code credentials in Spark's own Keychain (no password prompt on read)
    static func cacheCredentials(_ credentials: ClaudeCredentials) {
        save(credentials.accessToken, account: "oauth-token")
        save(credentials.accountTier.displayName, account: "account-tier")
    }

    /// Read cached account tier display name from Spark's own Keychain
    static func readCachedTierName() -> String? {
        read(account: "account-tier")
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
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            log.debug("read(\(account, privacy: .public)): no entry (OSStatus \(status))")
            return nil
        }
        log.debug("read(\(account, privacy: .public)): found")
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        log.debug("delete(\(account, privacy: .public)): OSStatus \(status)")
    }

    /// Read Claude Code CLI credentials from Keychain
    /// - Parameter silent: When `true`, suppresses the macOS password prompt.
    ///   Use `silent: true` for background/polling reads, `false` for user-initiated actions.
    static func readClaudeCodeCredentials(silent: Bool = false) -> ClaudeCredentials? {
        let mode = silent ? "silent" : "prompted"
        log.notice("readClaudeCode(\(mode, privacy: .public)): reading credentials")

        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "Claude Code-credentials" as CFString,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        if silent {
            query[kSecUseAuthenticationUI] = kSecUseAuthenticationUISkip
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            log.error("readClaudeCode(\(mode, privacy: .public)): keychain read failed (OSStatus \(status))")
            return nil
        }

        guard let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else {
            log.error("readClaudeCode(\(mode, privacy: .public)): keychain entry found but token missing or invalid")
            return nil
        }

        let subscriptionType = oauth["subscriptionType"] as? String
        let rateLimitTier = oauth["rateLimitTier"] as? String

        log.notice("readClaudeCode(\(mode, privacy: .public)): success (tier: \(subscriptionType ?? "unknown", privacy: .public))")

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

    /// Restore from cached displayName (e.g. "Max 5x" → plan: "Max", multiplier: "5x")
    init(displayName: String) {
        let parts = displayName.split(separator: " ", maxSplits: 1)
        self.plan = String(parts.first ?? "Free")
        self.multiplier = parts.count > 1 ? String(parts[1]) : nil
    }

    init(plan: String, multiplier: String?) {
        self.plan = plan
        self.multiplier = multiplier
    }

    static let free = AccountTier(plan: "Free", multiplier: nil)
}
