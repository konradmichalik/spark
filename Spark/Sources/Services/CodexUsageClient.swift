import Foundation

/// Fetches the ChatGPT plan's Codex limits from the endpoint the Codex CLI uses for `/status`.
/// Undocumented, so decoding is lenient (see `CodexUsageResponse`) and errors reuse
/// `UsageClient.ClientError` to share the Claude handling for 401 and 429.
enum CodexUsageClient {
    private static let usageURL = URL(staticString: "https://chatgpt.com/backend-api/wham/usage")

    static func buildRequest(credentials: CodexCredentials) -> URLRequest {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountId = credentials.accountId {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        return request
    }

    static func error(forStatus status: Int) -> UsageClient.ClientError? {
        switch status {
        case 200: nil
        case 401, 403: .unauthorized
        case 429: .rateLimited
        default: .serverError(status)
        }
    }

    static func fetchUsage(credentials: CodexCredentials) async throws -> CodexUsageResponse {
        let (data, response) = try await URLSession.shared.data(for: buildRequest(credentials: credentials))
        guard let http = response as? HTTPURLResponse else { throw UsageClient.ClientError.networkError }
        if let error = error(forStatus: http.statusCode) { throw error }
        return try JSONDecoder().decode(CodexUsageResponse.self, from: data)
    }
}
