@testable import Spark
import XCTest

final class ReportLayoutTests: XCTestCase {
    func testWindowGrowsToFitTheContent() {
        let height = ReportLayout.windowHeight(current: 660, visibleScroll: 560, content: 900, screenHeight: 1200, minimum: 420)
        XCTAssertEqual(height, 1000)
    }

    func testWindowShrinksWithShorterContent() {
        let height = ReportLayout.windowHeight(current: 1000, visibleScroll: 900, content: 500, screenHeight: 1200, minimum: 420)
        XCTAssertEqual(height, 600)
    }

    func testWindowNeverExceedsTheScreenOrGoesBelowTheMinimum() {
        XCTAssertEqual(ReportLayout.windowHeight(current: 660, visibleScroll: 560, content: 2000, screenHeight: 900, minimum: 420), 900)
        XCTAssertEqual(ReportLayout.windowHeight(current: 660, visibleScroll: 560, content: 100, screenHeight: 900, minimum: 420), 420)
    }
}
