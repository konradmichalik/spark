import Foundation

/// Spark's own secrets, stored as a single keychain entry (one ACL, one prompt).
/// Consolidating the formerly per-field entries caps macOS password prompts at one
/// after each ad-hoc-signed release update instead of one per field.
struct SparkCredentialStore: Codable, Equatable {
    var longLivedToken: String?
    var oauthToken: String?
    var accountTier: String?
    var refreshToken: String?
    var tokenExpiresAt: Double?

    static let empty = SparkCredentialStore()

    var isEmpty: Bool { self == .empty }

    init(
        longLivedToken: String? = nil,
        oauthToken: String? = nil,
        accountTier: String? = nil,
        refreshToken: String? = nil,
        tokenExpiresAt: Double? = nil
    ) {
        self.longLivedToken = longLivedToken
        self.oauthToken = oauthToken
        self.accountTier = accountTier
        self.refreshToken = refreshToken
        self.tokenExpiresAt = tokenExpiresAt
    }

    init?(jsonData: Data) {
        guard let decoded = try? JSONDecoder().decode(SparkCredentialStore.self, from: jsonData) else {
            return nil
        }
        self = decoded
    }

    var jsonData: Data? {
        try? JSONEncoder().encode(self)
    }

    /// Assemble a store from the legacy per-field keychain values during migration.
    static func fromLegacy(
        longLivedToken: String?,
        oauthToken: String?,
        accountTier: String?,
        refreshToken: String?,
        tokenExpiresAtRaw: String?
    ) -> SparkCredentialStore {
        SparkCredentialStore(
            longLivedToken: longLivedToken,
            oauthToken: oauthToken,
            accountTier: accountTier,
            refreshToken: refreshToken,
            tokenExpiresAt: tokenExpiresAtRaw.flatMap(Double.init)
        )
    }
}
