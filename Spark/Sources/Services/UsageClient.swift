import Foundation

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
    // swiftlint:enable force_unwrapping

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
