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

final class StatusDotIconTests: XCTestCase {
    func testEveryStatusHasADotIcon() {
        XCTAssertEqual(ClaudeServiceStatus.operational.dotIcon, .statusOK)
        XCTAssertEqual(ClaudeServiceStatus.none.dotIcon, .statusOK)
        XCTAssertEqual(ClaudeServiceStatus.degradedPerformance.dotIcon, .statusDegraded)
        XCTAssertEqual(ClaudeServiceStatus.partialOutage.dotIcon, .statusDegraded)
        XCTAssertEqual(ClaudeServiceStatus.majorOutage.dotIcon, .statusOutage)
        XCTAssertEqual(ClaudeServiceStatus.unknown.dotIcon, .statusUnknown)
    }

    func testStatusIconsAreDistinctAndInsideTheGrid() {
        let icons: [DotIcon] = [.statusOK, .statusDegraded, .statusOutage, .statusUnknown]
        let patterns = icons.map { icon in icon.dots.map { "\($0.column),\($0.row)" }.sorted().joined(separator: ";") }
        XCTAssertEqual(Set(patterns).count, icons.count)
        for icon in icons {
            for dot in icon.dots {
                XCTAssertTrue((0..<icon.grid).contains(dot.column) && (0..<icon.grid).contains(dot.row), "\(icon) \(dot)")
            }
        }
    }
}
