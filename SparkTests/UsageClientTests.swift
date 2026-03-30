import XCTest
@testable import Spark

final class UsageClientTests: XCTestCase {

    // MARK: - ClientError

    func testClientErrorDescriptions() {
        XCTAssertNotNil(UsageClient.ClientError.unauthorized.errorDescription)
        XCTAssertNotNil(UsageClient.ClientError.rateLimited.errorDescription)
        XCTAssertNotNil(UsageClient.ClientError.networkError.errorDescription)
        XCTAssertNotNil(UsageClient.ClientError.serverError(500).errorDescription)
    }

    func testClientErrorEquality() {
        XCTAssertEqual(UsageClient.ClientError.unauthorized, .unauthorized)
        XCTAssertEqual(UsageClient.ClientError.rateLimited, .rateLimited)
        XCTAssertEqual(UsageClient.ClientError.serverError(500), .serverError(500))
        XCTAssertNotEqual(UsageClient.ClientError.serverError(500), .serverError(502))
    }
}
