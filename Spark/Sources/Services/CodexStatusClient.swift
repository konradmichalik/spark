import Foundation

/// Reads the Codex components from the OpenAI status page. Errors reuse `UsageClient.ClientError`.
enum CodexStatusClient {
    static let statusURL = URL(staticString: "https://status.openai.com/proxy/status.openai.com")

    static func fetchStatus() async throws -> CodexStatusSnapshot {
        var request = URLRequest(url: statusURL)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageClient.ClientError.networkError }
        guard http.statusCode == 200 else { throw UsageClient.ClientError.serverError(http.statusCode) }
        return try JSONDecoder().decode(CodexStatusResponse.self, from: data).snapshot()
    }
}
