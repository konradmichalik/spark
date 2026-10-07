import XCTest
@testable import Spark

final class DotBarLayoutTests: XCTestCase {
    private func count(_ layout: DotBarLayout, _ dot: DotBarLayout.Dot) -> Int {
        layout.dots.filter { $0 == dot }.count
    }

    func testDotCountFollowsWidthAndPitch() {
        XCTAssertEqual(DotBarLayout.count(width: 292, pitch: 6), 48)
        XCTAssertEqual(DotBarLayout.count(width: 292, pitch: 4), 73)
        XCTAssertEqual(DotBarLayout.count(width: 0, pitch: 6), 0)
        XCTAssertEqual(DotBarLayout.count(width: 100, pitch: 0), 0)
        XCTAssertEqual(DotBarLayout.count(width: .infinity, pitch: 6), 0)
    }

    func testFilledDotsRoundToTheNearestDot() {
        let layout = DotBarLayout(count: 48, value: 45)
        XCTAssertEqual(count(layout, .filled), 22)
        XCTAssertEqual(count(layout, .track), 26)
        XCTAssertEqual(Array(layout.dots.prefix(22)), Array(repeating: .filled, count: 22))
    }

    func testProjectionFillsTheGapAfterTheValue() {
        let layout = DotBarLayout(count: 48, value: 45, projected: 79)
        XCTAssertEqual(count(layout, .filled), 22)
        XCTAssertEqual(count(layout, .projected), 16)
        XCTAssertEqual(layout.dots[22], .projected)
    }

    func testProjectionBelowTheValueAddsNothing() {
        XCTAssertEqual(count(DotBarLayout(count: 48, value: 45, projected: 30), .projected), 0)
    }

    func testMarkerSitsAtTheElapsedShare() {
        XCTAssertEqual(DotBarLayout(count: 48, value: 0, marker: 54).markerIndex, 26)
        XCTAssertEqual(DotBarLayout(count: 48, value: 0, marker: 100).markerIndex, 47)
        XCTAssertNil(DotBarLayout(count: 48, value: 0).markerIndex)
        XCTAssertNil(DotBarLayout(count: 0, value: 0, marker: 50).markerIndex)
    }

    func testOutOfRangeValuesStayInsideTheBar() {
        XCTAssertEqual(count(DotBarLayout(count: 48, value: .nan), .filled), 0)
        XCTAssertEqual(count(DotBarLayout(count: 48, value: -5), .filled), 0)
        XCTAssertEqual(count(DotBarLayout(count: 48, value: 150), .filled), 48)
        XCTAssertEqual(DotBarLayout(count: 48, value: 50, projected: .infinity).dots.count, 48)
        XCTAssertEqual(DotBarLayout(count: -3, value: 50).dots, [])
    }
}
