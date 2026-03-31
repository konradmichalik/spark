import XCTest
@testable import Spark

final class ThemeTests: XCTestCase {

    // MARK: - TimeInterval.shortDuration

    func testShortDurationMinutes() {
        XCTAssertEqual(TimeInterval(90).shortDuration, "1m")
        XCTAssertEqual(TimeInterval(300).shortDuration, "5m")
        XCTAssertEqual(TimeInterval(3540).shortDuration, "59m")
    }

    func testShortDurationHoursAndMinutes() {
        XCTAssertEqual(TimeInterval(3600).shortDuration, "1h 0m")
        XCTAssertEqual(TimeInterval(5400).shortDuration, "1h 30m")
        XCTAssertEqual(TimeInterval(7200).shortDuration, "2h 0m")
    }

    func testShortDurationDays() {
        XCTAssertEqual(TimeInterval(86400).shortDuration, "1d")
        XCTAssertEqual(TimeInterval(90000).shortDuration, "1d 1h")
        XCTAssertEqual(TimeInterval(172800).shortDuration, "2d")
    }

    func testShortDurationZero() {
        XCTAssertEqual(TimeInterval(0).shortDuration, "0m")
    }
}
