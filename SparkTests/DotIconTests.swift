@testable import Spark
import AppKit
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

final class SettingsDotIconTests: XCTestCase {
    private let tabs: [DotIcon] = [.general, .menuBar, .display, .connections, .notifications, .status, .about]

    func testTabIconsUseAFiveByFiveGrid() {
        for icon in tabs {
            XCTAssertEqual(icon.grid, 5, "\(icon)")
            XCTAssertFalse(icon.dots.isEmpty, "\(icon)")
            for dot in icon.dots {
                XCTAssertTrue((0..<5).contains(dot.column) && (0..<5).contains(dot.row), "\(icon) \(dot)")
            }
        }
    }

    func testTabIconsAreDistinct() {
        let patterns = tabs.map { icon in icon.dots.map { "\($0.column),\($0.row),\($0.isFilled)" }.sorted().joined(separator: ";") }
        XCTAssertEqual(Set(patterns).count, tabs.count)
    }

    func testTemplateImageMatchesTheRequestedSize() {
        let image = DotIcon.status.templateImage(size: 18)
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
    }
}
