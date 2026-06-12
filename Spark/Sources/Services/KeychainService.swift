import Foundation
import os
import Security

enum KeychainService {
    private static let service = "com.konradmichalik.spark"
    private static let log = Logger(subsystem: "com.konradmichalik.spark", category: "auth")

    /// All of Spark's own secrets live in ONE keychain entry. Each keychain item
    /// carries its own ACL bound to the app's code signature; ad-hoc signed builds
    /// get a fresh signature on every release, so a separate item per field meant one
    /// macOS password prompt per field after each update. Consolidating to a single
    /// entry caps that at a single prompt.
    private static let storeAccount = "spark-store"

    /// Legacy per-field accounts, migrated into `storeAccount` on first launch.
    static let longLivedTokenAccount = "long-lived-token"
    private static let legacyOAuthAccount = "oauth-token"
    private static let legacyTierAccount = "account-tier"
    private static let legacyRefreshAccount = "refresh-token"
    private static let legacyExpiresAtAccount = "token-expires-at"

    // MARK: - Long-lived Token (user-provided via `claude setup-token`)

    /// Trim and validate a user-pasted long-lived token. Returns the cleaned
    /// token, or nil if it doesn't look like a Claude OAuth token (`sk-ant-` prefix,
    /// length >= 10). Centralizes trim + format check in one place.
    static func cleanedLongLivedToken(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10, trimmed.hasPrefix("sk-ant-") else { return nil }
        return trimmed
    }

    static func saveLongLivedToken(_ cleaned: String) {
        update { $0.longLivedToken = cleaned }
    }

    static func readLongLivedToken() -> String? {
        loadStore().longLivedToken
    }

    static func deleteLongLivedToken() {
        update { $0.longLivedToken = nil }
    }

    // MARK: - Cached Claude Code credentials (Spark's own copy, no prompt to read)

    static func saveOAuthToken(_ token: String) {
        update { $0.oauthToken = token }
    }

    static func readCachedOAuthToken() -> String? {
        loadStore().oauthToken
    }

    /// Cache Claude Code credentials in Spark's own keychain entry (no password prompt on read).
    static func cacheCredentials(_ credentials: ClaudeCredentials) {
        update { store in
            store.oauthToken = credentials.accessToken
            store.accountTier = credentials.accountTier.displayName
            if let refresh = credentials.refreshToken {
                store.refreshToken = refresh
            }
            if let expiresAt = credentials.expiresAt {
                store.tokenExpiresAt = expiresAt.timeIntervalSince1970
            }
        }
    }

    /// Read cached account tier display name from Spark's own keychain entry.
    static func readCachedTierName() -> String? {
        loadStore().accountTier
    }

    /// Read cached refresh token + expiry from Spark's own keychain entry (no prompt).
    static func readCachedRefreshToken() -> (token: String, expiresAt: Date?)? {
        let store = loadStore()
        guard let token = store.refreshToken, !token.isEmpty else { return nil }
        let expiresAt = store.tokenExpiresAt.map { Date(timeIntervalSince1970: $0) }
        return (token, expiresAt)
    }

    /// Persist a refreshed OAuth token pair. Refresh token is preserved when the server
    /// does not rotate it. Expiry is recomputed from `expiresIn` seconds.
    static func saveRefreshedTokens(_ response: RefreshTokenResponse) {
        let expiry = Date().addingTimeInterval(TimeInterval(response.expiresIn))
        update { store in
            store.oauthToken = response.accessToken
            if let rotated = response.refreshToken {
                store.refreshToken = rotated
            }
            store.tokenExpiresAt = expiry.timeIntervalSince1970
        }
    }

    /// Clear the credentials a logout removes (token, tier, long-lived token),
    /// matching the previous per-field deletion behavior.
    static func clearForLogout() {
        update { store in
            store.oauthToken = nil
            store.accountTier = nil
            store.longLivedToken = nil
        }
    }

    // MARK: - Consolidated store I/O

    /// One-time migration from the legacy per-field entries into the single store,
    /// plus an ACL rebind to the current build signature. Call once at launch BEFORE
    /// any other read so that subsequent reads in this session are prompt-free.
    ///
    /// - Existing consolidated entry: re-saved (delete + add) so its ACL is bound to
    ///   the current build — a single "Allow" then keeps every later launch silent.
    /// - No consolidated entry yet: legacy fields are read once (may prompt per field,
    ///   one time only), written as one entry, and the legacy entries deleted.
    static func migrateAndRebindStore() {
        if let existing = readRawStore() {
            log.notice("store: rebinding ACL to current build signature")
            writeStore(existing)
            return
        }

        log.notice("store: migrating legacy per-field entries")
        let migrated = SparkCredentialStore.fromLegacy(
            longLivedToken: readLegacy(longLivedTokenAccount),
            oauthToken: readLegacy(legacyOAuthAccount),
            accountTier: readLegacy(legacyTierAccount),
            refreshToken: readLegacy(legacyRefreshAccount),
            tokenExpiresAtRaw: readLegacy(legacyExpiresAtAccount)
        )

        guard !migrated.isEmpty else {
            log.info("store: nothing to migrate")
            return
        }

        writeStore(migrated)
        [longLivedTokenAccount, legacyOAuthAccount, legacyTierAccount,
         legacyRefreshAccount, legacyExpiresAtAccount].forEach { delete(account: $0) }
        log.notice("store: migration complete")
    }

    private static func loadStore() -> SparkCredentialStore {
        readRawStore() ?? .empty
    }

    /// Read-modify-write the single store entry. All callers run on the main actor,
    /// so the non-atomic read/write is effectively serialized.
    private static func update(_ mutate: (inout SparkCredentialStore) -> Void) {
        var store = loadStore()
        mutate(&store)
        writeStore(store)
    }

    private static func readRawStore() -> SparkCredentialStore? {
        guard let data = readData(account: storeAccount) else { return nil }
        return SparkCredentialStore(jsonData: data)
    }

    private static func writeStore(_ store: SparkCredentialStore) {
        guard !store.isEmpty else {
            delete(account: storeAccount)
            return
        }
        guard let data = store.jsonData else {
            log.error("writeStore: JSON encoding failed")
            return
        }
        writeData(data, account: storeAccount)
    }

    // MARK: - Low-level keychain helpers

    /// Write `data` under `account`. Deletes first so a fresh ACL is created with the
    /// current code signature — prevents stale-ACL prompts after ad-hoc re-signing.
    private static func writeData(_ data: Data, account: String) {
        delete(account: account)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            log.info("write(\(account, privacy: .public)): success")
        } else {
            log.error("write(\(account, privacy: .public)): failed (OSStatus \(status))")
        }
    }

    private static func readData(account: String) -> Data? {
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
        return data
    }

    private static func readLegacy(_ account: String) -> String? {
        readData(account: account).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func delete(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        log.debug("delete(\(account, privacy: .public)): OSStatus \(status)")
    }

    // MARK: - Claude Code CLI credentials (separate keychain, owned by Claude Code)

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
