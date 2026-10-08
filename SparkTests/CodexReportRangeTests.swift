import XCTest
@testable import Spark

final class CodexReportRangeTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        return calendar
    }()

    private func date(_ day: String, time: String = "00:00") throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return try XCTUnwrap(formatter.date(from: "\(day) \(time)"))
    }

    private func range(
        period: ReportPeriod = .week, offset: Int = 0, now: Date
    ) -> CodexReportRange {
        let report = PeriodReport.build(rollups: [:], period: period, periodOffset: offset, now: now, calendar: calendar)
        return CodexReportRange(report: report, calendar: calendar)
    }

    func testCurrentWeekLowerBoundsStartAtMidnight() throws {
        let range = range(now: try date("2026-10-08", time: "18:00"))
        XCTAssertEqual(range.start, try date("2026-10-01"))
        XCTAssertEqual(range.previousStart, try date("2026-09-24"))
        XCTAssertNil(range.until)
    }

    func testTimeOfDayDoesNotChangeTheRange() throws {
        let evening = range(now: try date("2026-10-08", time: "18:00"))
        let morning = range(now: try date("2026-10-08", time: "09:00"))
        XCTAssertEqual(evening, morning)
        let pastEvening = range(offset: 1, now: try date("2026-10-08", time: "18:00"))
        let pastMorning = range(offset: 1, now: try date("2026-10-08", time: "09:00"))
        XCTAssertEqual(pastEvening, pastMorning)
    }

    func testPastWeekEndsAtTheStartOfTheDayAfterItsLastDay() throws {
        let range = range(offset: 1, now: try date("2026-10-08", time: "18:00"))
        XCTAssertEqual(range.start, try date("2026-09-24"))
        XCTAssertEqual(range.until, try date("2026-10-01"))
    }

    func testPastMonth() throws {
        let range = range(period: .month, offset: 1, now: try date("2026-10-08", time: "18:00"))
        XCTAssertEqual(range.start, try date("2026-09-01"))
        XCTAssertEqual(range.until, try date("2026-10-01"))
        XCTAssertEqual(range.previousStart, try date("2026-08-01"))
    }

    func testUntilIsMidnightAcrossDaylightSavingChange() throws {
        // Berlin turns its clocks back on 2026-10-25 (a 25 hour day) and forward on 2026-03-29.
        let autumn = range(offset: 1, now: try date("2026-11-03", time: "18:00"))
        XCTAssertEqual(autumn.start, try date("2026-10-20"))
        XCTAssertEqual(autumn.until, try date("2026-10-27"))
        let spring = range(offset: 1, now: try date("2026-04-06", time: "18:00"))
        XCTAssertEqual(spring.start, try date("2026-03-23"))
        XCTAssertEqual(spring.until, try date("2026-03-30"))
    }
}
