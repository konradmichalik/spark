import XCTest
@testable import Spark

final class DotRingLayoutTests: XCTestCase {
    func testPointsStartAtTwelveOClockAndRunClockwise() {
        let points = DotRingLayout.points(count: 12, radius: 10, center: CGPoint(x: 50, y: 50))
        XCTAssertEqual(points.count, 12)
        XCTAssertEqual(points[0].x, 50, accuracy: 0.001)
        XCTAssertEqual(points[0].y, 40, accuracy: 0.001)
        XCTAssertEqual(points[3].x, 60, accuracy: 0.001)
        XCTAssertEqual(points[3].y, 50, accuracy: 0.001)
        XCTAssertTrue(DotRingLayout.points(count: 0, radius: 10, center: .zero).isEmpty)
    }

    func testGapLeavesSlotsFreeAroundTwelveOClock() {
        let points = DotRingLayout.points(count: 10, radius: 10, center: CGPoint(x: 50, y: 50), gap: 2)
        XCTAssertEqual(points.count, 10)
        let first = 1.5 / 12 * Double.pi * 2 - .pi / 2
        XCTAssertEqual(points[0].x, 50 + 10 * cos(first), accuracy: 0.001)
        XCTAssertEqual(points[0].y, 50 + 10 * sin(first), accuracy: 0.001)
        XCTAssertEqual(points[9].x, 50 - 10 * cos(first), accuracy: 0.001)
        XCTAssertEqual(points[9].y, points[0].y, accuracy: 0.001)
    }

    func testPartialDotIsProportional() {
        let opacities = DotRingLayout.partialOpacities(count: 12, value: 45)
        XCTAssertEqual(Array(opacities.prefix(5)), Array(repeating: 1, count: 5))
        XCTAssertEqual(opacities[5], 0.28 + 0.72 * 0.4, accuracy: 0.001)
        XCTAssertEqual(Array(opacities.suffix(6)), Array(repeating: 0.28, count: 6))
    }

    func testEmptyAndFullRings() {
        XCTAssertEqual(DotRingLayout.partialOpacities(count: 12, value: 0), Array(repeating: 0.28, count: 12))
        XCTAssertEqual(DotRingLayout.partialOpacities(count: 12, value: 100), Array(repeating: 1, count: 12))
    }

    func testOutOfRangeValuesClamp() {
        XCTAssertEqual(DotRingLayout.partialOpacities(count: 12, value: 250), Array(repeating: 1, count: 12))
        XCTAssertEqual(DotRingLayout.partialOpacities(count: 12, value: -10), Array(repeating: 0.28, count: 12))
        XCTAssertEqual(DotRingLayout.partialOpacities(count: 12, value: .nan), Array(repeating: 0.28, count: 12))
        XCTAssertEqual(DotRingLayout.partialOpacities(count: -1, value: 50), [])
    }
}
