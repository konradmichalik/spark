@testable import Spark
import XCTest

final class ActivityFiguresTests: XCTestCase {
    private let calendar = TestCalendar.berlin()

    private func date(_ day: String) -> Date {
        TestCalendar.date(day, calendar: calendar)
    }

    private func figures(_ start: String, _ end: String, today: String, _ tokens: [String: Int]) -> ActivityFigures {
        let cells = ActivityCalendar.rows(
            start: date(start), end: date(end), today: date(today), dayTokens: tokens, calendar: calendar
        ).flatMap { $0 }
        return ActivityFigures(cells: cells)
    }

    func testEmptyData() {
        let result = figures("2026-10-05", "2026-10-11", today: "2026-10-09", [:])
        XCTAssertEqual(result.activeDays, 0)
        XCTAssertEqual(result.totalDays, 5, "Only days up to today count")
        XCTAssertEqual(result.longestStreak, 0)
        XCTAssertNil(result.busiest)
    }

    func testStreakSpansTheWeekBoundaryAndStopsAtGaps() {
        // Sat 10-10 to Tue 10-13 is four days in a row across Sunday and Monday, then a gap.
        let tokens = ["2026-10-06": 1, "2026-10-08": 1, "2026-10-10": 5, "2026-10-11": 5, "2026-10-12": 5, "2026-10-13": 5, "2026-10-15": 9]
        let result = figures("2026-10-05", "2026-10-18", today: "2026-10-18", tokens)
        XCTAssertEqual(result.activeDays, 7)
        XCTAssertEqual(result.longestStreak, 4)
    }

    func testFutureDaysAreExcluded() {
        let tokens = ["2026-10-05": 1, "2026-10-06": 1, "2026-10-07": 999, "2026-10-08": 999]
        let result = figures("2026-10-05", "2026-10-11", today: "2026-10-06", tokens)
        XCTAssertEqual(result.totalDays, 2)
        XCTAssertEqual(result.activeDays, 2)
        XCTAssertEqual(result.longestStreak, 2)
        XCTAssertEqual(result.busiest?.tokens, 1)
    }

    func testTieGoesToTheMostRecentDay() {
        let result = figures("2026-10-05", "2026-10-11", today: "2026-10-11", ["2026-10-06": 50, "2026-10-09": 50, "2026-10-07": 10])
        XCTAssertEqual(result.busiest?.dayKey, "2026-10-09")
    }

    func testSingleDay() {
        let result = figures("2026-10-05", "2026-10-05", today: "2026-10-05", ["2026-10-05": 7])
        XCTAssertEqual([result.activeDays, result.totalDays, result.longestStreak], [1, 1, 1])
        XCTAssertEqual(result.busiest?.tokens, 7)
    }

    func testScopeSumsFeedTheFigures() {
        let claude = ["2026-10-05": 10, "2026-10-06": 10]
        let codex = ["2026-10-06": 5, "2026-10-07": 40]
        let all = figures("2026-10-05", "2026-10-11", today: "2026-10-11", ReportScoping.dayTokens(.all, claude: claude, codex: codex))
        XCTAssertEqual(all.longestStreak, 3)
        XCTAssertEqual(all.busiest?.dayKey, "2026-10-07")
        let claudeOnly = figures("2026-10-05", "2026-10-11", today: "2026-10-11", ReportScoping.dayTokens(.claude, claude: claude, codex: codex))
        XCTAssertEqual(claudeOnly.activeDays, 2)
        XCTAssertEqual(claudeOnly.busiest?.dayKey, "2026-10-06")
    }

    func testWording() {
        XCTAssertEqual(ActivityFigures.streakUnit(1), "day")
        XCTAssertEqual(ActivityFigures.streakUnit(0), "days")
        XCTAssertEqual(ActivityFigures.streakUnit(4), "days")
    }
}
