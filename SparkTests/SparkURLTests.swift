import XCTest
@testable import Spark

final class SparkURLTests: XCTestCase {

    private func isShow(_ string: String) -> Bool {
        SparkURL.isShowRequest(URL(string: string)!)
    }

    func testShowOpensThePopover() {
        XCTAssertTrue(isShow("spark://show"))
    }

    func testSchemeAndHostIgnoreCase() {
        XCTAssertTrue(isShow("SPARK://Show"))
    }

    func testTrailingSlashStillMeansShow() {
        XCTAssertTrue(isShow("spark://show/"))
    }

    func testUnknownHostIsIgnored() {
        XCTAssertFalse(isShow("spark://hide"))
        XCTAssertFalse(isShow("spark://"))
    }

    func testUnknownPathIsIgnored() {
        XCTAssertFalse(isShow("spark://show/settings"))
    }

    func testOtherSchemeIsIgnored() {
        XCTAssertFalse(isShow("https://show"))
        XCTAssertFalse(isShow("sparkle://show"))
    }
}
