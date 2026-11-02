@testable import Spark
import XCTest

final class PeriodReportSessionTests: XCTestCase {
    private let calendar = TestCalendar.berlin()

    func testSessionCountPassesThrough() {
        let report = PeriodReport.build(rollups: [:], sessionCount: 7, now: TestCalendar.date("2026-08-21"), calendar: calendar)

        XCTAssertEqual(report.sessionCount, 7)
    }

    func testSessionCountDefaultsToZero() {
        let report = PeriodReport.build(rollups: [:], now: TestCalendar.date("2026-08-21"), calendar: calendar)

        XCTAssertEqual(report.sessionCount, 0)
    }
}
