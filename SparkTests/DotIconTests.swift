@testable import Spark
import XCTest

final class DotIconTests: XCTestCase {
    func testStatisticsIsThreeDotColumns() {
        let dots = DotIcon.statistics.dots
        XCTAssertEqual(dots.filter { $0.isFilled }.count, 2 + 4 + 3)
        XCTAssertEqual(Set(dots.map(\.column)), [0, 1, 2])
    }

    func testLimitsIsAPartlyFilledRing() {
        let dots = DotIcon.limits.dots
        XCTAssertEqual(dots.count, 8)
        XCTAssertEqual(dots.filter { $0.isFilled }.count, 5)
    }

    func testDotsStayInsideTheGrid() {
        for icon in [DotIcon.statistics, .limits] {
            for dot in icon.dots {
                XCTAssertTrue((0...3).contains(dot.column) && (0...3).contains(dot.row), "\(icon) \(dot)")
            }
        }
    }
}
