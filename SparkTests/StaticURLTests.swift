import XCTest
@testable import Spark

final class StaticURLTests: XCTestCase {
    func testBuildsTheURLFromALiteral() {
        XCTAssertEqual(URL(staticString: "https://status.claude.com").absoluteString, "https://status.claude.com")
    }
}
