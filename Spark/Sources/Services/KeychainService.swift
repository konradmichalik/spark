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
        if let refresh = credentials.refreshToken {
            save(refresh, account: "refresh-token")
        }
        if let expiresAt = credentials.expiresAt {
            save(String(expiresAt.timeIntervalSince1970), account: "token-expires-at")
        }
    }

    /// Read cached account tier display name from Spark's own Keychain
    static func readCachedTierName() -> String? {
        read(account: "account-tier")
    }

    /// Read cached refresh token + expiry from Spark's own Keychain (no prompt)
    static func readCachedRefreshToken() -> (token: String, expiresAt: Date?)? {
        guard let token = read(account: "refresh-token"), !token.isEmpty else { return nil }
        var expiresAt: Date?
        if let raw = read(account: "token-expires-at"), let seconds = TimeInterval(raw) {
            expiresAt = Date(timeIntervalSince1970: seconds)
        }
        return (token, expiresAt)
    }

    /// Persist a refreshed OAuth token pair. Refresh token is preserved when the server
    /// does not rotate it. Expiry is recomputed from `expiresIn` seconds.
    static func saveRefreshedTokens(_ response: RefreshTokenResponse) {
        save(response.accessToken, account: "oauth-token")
        if let rotated = response.refreshToken {
            save(rotated, account: "refresh-token")
        }
        let expiry = Date().addingTimeInterval(TimeInterval(response.expiresIn))
        save(String(expiry.timeIntervalSince1970), account: "token-expires-at")
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

        guard let data = result as? Data, let credentials = ClaudeCredentials(jsonData: data) else {
            log.error("readClaudeCode(\(mode, privacy: .public)): keychain entry found but token missing or invalid")
            return nil
        }

        log.notice(
            "readClaudeCode(\(mode, privacy: .public)): success (tier: \(credentials.subscriptionType ?? "unknown", privacy: .public))"
        )
        return credentials
    }

    /// Convenience: read just the token
    static func readClaudeCodeToken() -> String? {
        readClaudeCodeCredentials()?.accessToken
    }
}

struct ClaudeCredentials {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let subscriptionType: String?
    let rateLimitTier: String?

    init(
        accessToken: String,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        subscriptionType: String?,
        rateLimitTier: String?
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
    }

    /// Parse from the Claude Code keychain JSON blob.
    /// Shape: `{"claudeAiOauth": {"accessToken": "...", "refreshToken": "...", "expiresAt": <ms>, ...}}`
    init?(jsonData: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else {
            return nil
        }
        self.accessToken = token
        self.refreshToken = oauth["refreshToken"] as? String
        if let ms = oauth["expiresAt"] as? Double {
            self.expiresAt = Date(timeIntervalSince1970: ms / 1000)
        } else {
            self.expiresAt = nil
        }
        self.subscriptionType = oauth["subscriptionType"] as? String
        self.rateLimitTier = oauth["rateLimitTier"] as? String
    }

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
