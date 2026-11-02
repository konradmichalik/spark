@testable import Spark
import XCTest

final class ActivityFiguresTests: XCTestCase {
    private let calendar = TestCalendar.berlin()

    private func date(_ day: String) -> Date {
        TestCalendar.date(day, calendar: calendar)
    }

    private func figures(_ start: String, _ end: String, today: String, _ tokens: [String: Int]) -> ActivityFigures {
        let todayStart = calendar.startOfDay(for: date(today))
        let days = calendar.dayStarts(from: calendar.startOfDay(for: date(start)), through: calendar.startOfDay(for: date(end))).map { day in
            let key = TranscriptCache.dayKey(for: day, calendar: calendar)
            return ReportDay(
                date: day, key: key, claude: tokens[key] ?? 0, codex: 0, isToday: day == todayStart, isFuture: day > todayStart, note: nil
            )
        }
        return ActivityFigures(days: days)
    }

    func testDayStartsSurviveTheDSTChange() {
        // Europe/Berlin leaves summer time on 2026-10-25 (a 25-hour day).
        let days = calendar.dayStarts(from: calendar.startOfDay(for: date("2026-10-19")), through: calendar.startOfDay(for: date("2026-11-01")))
        XCTAssertEqual(days.count, 14)
        XCTAssertEqual(days.first.map { TranscriptCache.dayKey(for: $0, calendar: calendar) }, "2026-10-19")
        XCTAssertEqual(days.last.map { TranscriptCache.dayKey(for: $0, calendar: calendar) }, "2026-11-01")
        XCTAssertEqual(Set(days.map { TranscriptCache.dayKey(for: $0, calendar: calendar) }).count, 14)
    }

    func testStartAfterEndGivesNoDays() {
        XCTAssertTrue(calendar.dayStarts(from: date("2026-10-02"), through: date("2026-10-01")).isEmpty)
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
        XCTAssertEqual(result.busiest?.total, 1)
    }

    func testTieGoesToTheMostRecentDay() {
        let result = figures("2026-10-05", "2026-10-11", today: "2026-10-11", ["2026-10-06": 50, "2026-10-09": 50, "2026-10-07": 10])
        XCTAssertEqual(result.busiest?.key, "2026-10-09")
    }

    func testSingleDay() {
        let result = figures("2026-10-05", "2026-10-05", today: "2026-10-05", ["2026-10-05": 7])
        XCTAssertEqual([result.activeDays, result.totalDays, result.longestStreak], [1, 1, 1])
        XCTAssertEqual(result.busiest?.total, 7)
    }

    func testScopeSumsFeedTheFigures() {
        let claude = ["2026-10-05": 10, "2026-10-06": 10]
        let codex = ["2026-10-06": 5, "2026-10-07": 40]
        let all = figures("2026-10-05", "2026-10-11", today: "2026-10-11", ReportScoping.dayTokens(.all, claude: claude, codex: codex))
        XCTAssertEqual(all.longestStreak, 3)
        XCTAssertEqual(all.busiest?.key, "2026-10-07")
        let claudeOnly = figures("2026-10-05", "2026-10-11", today: "2026-10-11", ReportScoping.dayTokens(.claude, claude: claude, codex: codex))
        XCTAssertEqual(claudeOnly.activeDays, 2)
        XCTAssertEqual(claudeOnly.busiest?.key, "2026-10-06")
    }

    func testWording() {
        XCTAssertEqual(ActivityFigures.streakUnit(1), "day")
        XCTAssertEqual(ActivityFigures.streakUnit(0), "days")
        XCTAssertEqual(ActivityFigures.streakUnit(4), "days")
    }
}
