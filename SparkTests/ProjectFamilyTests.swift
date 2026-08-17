import XCTest
@testable import Spark

final class ProjectFamilyTests: XCTestCase {

    func testDisplayNameUsesLastPathComponentOfResolvedCwd() {
        XCTAssertEqual(
            ProjectFamily.displayName(forKey: "-Users-konrad-dev-typo3-routing", cwd: "/Users/konrad/dev/typo3-routing"),
            "typo3-routing"
        )
    }

    func testDisplayNameFallsBackToLastSegmentOfEncodedKeyWhenCwdIsMissing() {
        XCTAssertEqual(
            ProjectFamily.displayName(forKey: "-Users-konrad-dev-typo3-routing", cwd: nil),
            "routing"
        )
    }

    func testDisplayNameFallsBackWhenCwdIsEmpty() {
        XCTAssertEqual(
            ProjectFamily.displayName(forKey: "-Users-konrad-dev-typo3-routing", cwd: ""),
            "routing"
        )
    }

    func testDisplayNameHandlesEncodedKeyWithNoHyphens() {
        XCTAssertEqual(ProjectFamily.displayName(forKey: "orphan", cwd: nil), "orphan")
    }
}
