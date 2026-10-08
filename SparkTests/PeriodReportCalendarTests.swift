@testable import Spark
import XCTest

final class PeriodReportCalendarTests: XCTestCase {
    private let calendar = TestCalendar.berlin()

    private func date(_ day: String) -> Date {
        TestCalendar.date(day, calendar: calendar)
    }

    private func key(_ date: Date) -> String { TranscriptCache.dayKey(for: date, calendar: calendar) }

    private func report(period: ReportPeriod, offset: Int = 0) -> PeriodReport {
        PeriodReport.build(
            rollups: [:],
            dayTokens: ["2026-08-21": 5], period: period, periodOffset: offset, now: date("2026-08-21"), calendar: calendar
        )
    }

    func testCurrentWeekCalendarEndsToday() {
        let result = report(period: .week)
        XCTAssertEqual(key(result.calendarStart), "2026-08-15")
        XCTAssertEqual(key(result.calendarEnd), "2026-08-21")
        XCTAssertEqual(result.dayTokens["2026-08-21"], 5)
    }

    func testCurrentMonthCalendarRunsFromTheFirstToToday() {
        let result = report(period: .month)
        XCTAssertEqual(key(result.calendarStart), "2026-08-01")
        XCTAssertEqual(key(result.calendarEnd), "2026-08-21")
    }

    func testPastPeriodKeepsItsRange() {
        let result = report(period: .month, offset: 1)
        XCTAssertEqual(key(result.calendarStart), "2026-07-01")
        XCTAssertEqual(key(result.calendarEnd), "2026-07-31")
    }
}
