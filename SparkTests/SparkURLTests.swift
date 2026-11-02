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

    func testViewQueryStillCountsAsShow() {
        XCTAssertTrue(isShow("spark://show?view=week"))
    }

    private func view(_ string: String) -> String? {
        SparkURL.requestedView(URL(string: string)!)
    }

    func testViewParameterIsReturnedForKnownIds() {
        for id in ["session", "week", "today", "active"] {
            XCTAssertEqual(view("spark://show?view=\(id)"), id)
        }
    }

    func testViewParameterIgnoresCase() {
        XCTAssertEqual(view("spark://show?view=Active"), "active")
    }

    func testMissingOrUnknownViewIsNil() {
        XCTAssertNil(view("spark://show"))
        XCTAssertNil(view("spark://show?view="))
        XCTAssertNil(view("spark://show?view=month"))
        XCTAssertNil(view("spark://show?other=week"))
    }

    func testViewOnANonShowURLIsNil() {
        XCTAssertNil(view("spark://hide?view=week"))
    }

    func testOnlyActiveLeavesTheOverview() {
        XCTAssertEqual(SparkURL.screen(forView: "active"), .sessions)
        for id in ["session", "week", "today", "unknown"] {
            XCTAssertEqual(SparkURL.screen(forView: id), .overview)
        }
    }

    func testInfoPlistRegistersTheScheme() throws {
        let types = try XCTUnwrap(Bundle(for: AppDelegate.self).infoDictionary?["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }

        XCTAssertTrue(schemes.contains(SparkURL.scheme))
    }
}
