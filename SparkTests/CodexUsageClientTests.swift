import XCTest
@testable import Spark

final class CodexUsageClientTests: XCTestCase {

    func testRequestTargetsWhamUsageWithBearerAndAccountHeaders() {
        let request = CodexUsageClient.buildRequest(
            credentials: CodexCredentials(accessToken: "access-123", accountId: "acct-1")
        )

        XCTAssertEqual(request.url?.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "acct-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 10)
    }

    func testAccountHeaderOmittedWithoutAccountId() {
        let request = CodexUsageClient.buildRequest(
            credentials: CodexCredentials(accessToken: "access-123", accountId: nil)
        )

        XCTAssertNil(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"))
    }

    func testStatusCodeMapping() {
        XCTAssertNil(CodexUsageClient.error(forStatus: 200))
        XCTAssertEqual(CodexUsageClient.error(forStatus: 401), .unauthorized)
        XCTAssertEqual(CodexUsageClient.error(forStatus: 403), .unauthorized)
        XCTAssertEqual(CodexUsageClient.error(forStatus: 429), .rateLimited)
        XCTAssertEqual(CodexUsageClient.error(forStatus: 502), .serverError(502))
    }
}
