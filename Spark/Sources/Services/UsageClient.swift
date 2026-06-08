import Foundation

struct RefreshTokenResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

enum UsageClient {

    // MARK: - Errors

    enum ClientError: LocalizedError, Equatable {
        case unauthorized
        case rateLimited
        case networkError
        case serverError(Int)

        var errorDescription: String? {
            switch self {
            case .unauthorized: "Token expired. Refreshing automatically."
            case .rateLimited: "Rate limit reached."
            case .networkError: "Network error."
            case .serverError(let code): "Server error: \(code)"
            }
        }
    }

    // MARK: - API

    // swiftlint:disable force_unwrapping
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let statusURL = URL(string: "https://status.claude.com/api/v2/summary.json")!
    private static let refreshURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    // swiftlint:enable force_unwrapping

    /// Claude Code's public OAuth client ID (extracted from the CLI binary)
    static let oauthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    // MARK: - Refresh

    static func buildRefreshRequest(refreshToken: String) -> URLRequest {
        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": oauthClientID
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func decodeRefreshResponse(_ data: Data) throws -> RefreshTokenResponse {
        try JSONDecoder().decode(RefreshTokenResponse.self, from: data)
    }

    /// Exchange a refresh token for a new access token (no Keychain prompt).
    /// Throws `ClientError.unauthorized` on 4xx (refresh token revoked / rotated).
    static func refreshAccessToken(refreshToken: String) async throws -> RefreshTokenResponse {
        let request = buildRefreshRequest(refreshToken: refreshToken)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.networkError }
        switch http.statusCode {
        case 200:
            return try decodeRefreshResponse(data)
        case 400, 401, 403:
            throw ClientError.unauthorized
        case 429:
            throw ClientError.rateLimited
        default:
            throw ClientError.serverError(http.statusCode)
        }
    }

    static func fetchUsage(token: String) async throws -> UsageAPIResponse {
        let url = usageURL
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ClientError.networkError
        }

        switch http.statusCode {
        case 200:
            return try JSONDecoder().decode(UsageAPIResponse.self, from: data)
        case 401, 403:
            throw ClientError.unauthorized
        case 429:
            throw ClientError.rateLimited
        default:
            throw ClientError.serverError(http.statusCode)
        }
    }

    static func fetchStatus() async throws -> StatusPageResponse {
        let url = statusURL
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(StatusPageResponse.self, from: data)
    }
}
