@testable import Spark
import XCTest

final class ActivityCalendarTests: XCTestCase {
    private func makeCalendar(firstWeekday: Int = 2) -> Calendar {
        TestCalendar.berlin(firstWeekday: firstWeekday)
    }

    private func day(_ string: String, calendar: Calendar) -> Date {
        TestCalendar.date(string, calendar: calendar)
    }

    private func rows(
        _ start: String, _ end: String, today: String, tokens: [String: Int] = [:], calendar: Calendar? = nil
    ) -> [[ActivityCell]] {
        let calendar = calendar ?? makeCalendar()
        return ActivityCalendar.rows(
            start: day(start, calendar: calendar), end: day(end, calendar: calendar), today: day(today, calendar: calendar),
            dayTokens: tokens, calendar: calendar
        )
    }

    func testMonthStartingMidWeekIsPaddedBeforeTheFirstDay() {
        // 2026-10-01 is a Thursday, so a Monday-first row starts with three padding cells.
        let result = rows("2026-10-01", "2026-10-31", today: "2026-11-15")
        XCTAssertEqual(result.count, 5)
        XCTAssertTrue(result.allSatisfy { $0.count == 7 })
        XCTAssertEqual(result[0].map(\.isOutsideRange), [true, true, true, false, false, false, false])
        XCTAssertEqual(result[0][3].dayKey, "2026-10-01")
        XCTAssertEqual(result[4].map(\.isOutsideRange), [false, false, false, false, false, false, true], "Trailing cells pad the last row")
    }

    func testWeekOfSevenDaysSpansTwoRowsUnlessAligned() {
        let aligned = rows("2026-10-05", "2026-10-11", today: "2026-10-20")
        XCTAssertEqual(aligned.count, 1)
        XCTAssertEqual(aligned[0].map(\.dayKey).first, "2026-10-05")
        let unaligned = rows("2026-10-03", "2026-10-09", today: "2026-10-20")
        XCTAssertEqual(unaligned.count, 2)
    }

    func testLevelsAreRelativeToTheBusiestDay() {
        let tokens = [
            "2026-10-05": 100, "2026-10-06": 20, "2026-10-07": 50, "2026-10-08": 90, "2026-10-09": 1
        ]
        let cells = rows("2026-10-05", "2026-10-11", today: "2026-10-20", tokens: tokens)[0]
        XCTAssertEqual(cells.map(\.level), [3, 1, 2, 3, 1, 0, 0])
    }

    func testNoUseIsLevelZeroAndAnEmptyMapHasNoPeak() {
        let cells = rows("2026-10-05", "2026-10-11", today: "2026-10-20")[0]
        XCTAssertTrue(cells.allSatisfy { $0.level == 0 && $0.tokens == 0 })
    }

    func testTodayIsMarkedAndLaterDaysAreFuture() {
        let cells = rows("2026-10-05", "2026-10-11", today: "2026-10-07")[0]
        XCTAssertEqual(cells.map(\.isToday), [false, false, true, false, false, false, false])
        XCTAssertEqual(cells.map(\.isFuture), [false, false, false, true, true, true, true])
    }

    func testFirstWeekdaySundayShiftsTheColumns() {
        let calendar = makeCalendar(firstWeekday: 1)
        // 2026-10-04 is a Sunday: a Sunday-first week starts on it.
        let result = rows("2026-10-04", "2026-10-10", today: "2026-10-20", calendar: calendar)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].first?.dayKey, "2026-10-04")
        XCTAssertEqual(ActivityCalendar.weekdayInitials(calendar: calendar, locale: Locale(identifier: "en_US")).first, "S")
    }

    func testWeekdayInitialsStartOnMonday() {
        let initials = ActivityCalendar.weekdayInitials(calendar: makeCalendar(), locale: Locale(identifier: "en_US"))
        XCTAssertEqual(initials, ["M", "T", "W", "T", "F", "S", "S"])
    }

    func testIterationSurvivesTheDSTChange() {
        // Europe/Berlin leaves summer time on 2026-10-25 (a 25-hour day).
        let result = rows("2026-10-19", "2026-11-01", today: "2026-12-01")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.flatMap { $0 }.map(\.dayKey).first, "2026-10-19")
        XCTAssertEqual(result.flatMap { $0 }.map(\.dayKey).last, "2026-11-01")
        XCTAssertEqual(Set(result.flatMap { $0 }.map(\.dayKey)).count, 14)
    }

    func testStartAfterEndGivesNoRows() {
        XCTAssertTrue(rows("2026-10-02", "2026-10-01", today: "2026-10-03").isEmpty)
    }

    func testSummaryNamesActiveDaysAndTheBusiestDay() {
        let calendar = makeCalendar()
        let cells = rows("2026-10-05", "2026-10-11", today: "2026-10-09", tokens: ["2026-10-05": 1200, "2026-10-07": 4_500_000])
        let summary = ActivityCalendar.summary(ActivityFigures(cells: cells.flatMap { $0 }), calendar: calendar, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(summary.hasPrefix("Used on 2 of 5 days"), summary)
        XCTAssertTrue(summary.contains("busiest day"), summary)
        XCTAssertTrue(summary.contains("4.5M tokens"), summary)
    }

    func testSummaryWithoutUse() {
        let figures = ActivityFigures(cells: rows("2026-10-05", "2026-10-11", today: "2026-10-09").flatMap { $0 })
        XCTAssertEqual(ActivityCalendar.summary(figures, calendar: makeCalendar(), locale: Locale(identifier: "en_US")), "No use in this period")
    }

    /// The spoken summary and the figures beside the calendar name the same day: the latest one on a tie.
    func testSummaryNamesTheLatestBusiestDayOnATie() {
        let cells = rows("2026-10-05", "2026-10-11", today: "2026-10-09", tokens: ["2026-10-05": 900, "2026-10-07": 900])
        let figures = ActivityFigures(cells: cells.flatMap { $0 })
        let summary = ActivityCalendar.summary(figures, calendar: makeCalendar(), locale: Locale(identifier: "en_US"))
        XCTAssertTrue(summary.contains("Wed"), summary)
    }

    func testTooltipTexts() {
        let cells = rows("2026-10-05", "2026-10-11", today: "2026-10-20", tokens: ["2026-10-05": 1_234_000])[0]
        XCTAssertEqual(ActivityCalendar.tooltipBody(cells[0]), "1.2M tokens")
        XCTAssertEqual(ActivityCalendar.tooltipBody(cells[1]), "No use")
    }
}
