@testable import Spark
import XCTest

final class ReportDaySeriesTests: XCTestCase {
    private let calendar = TestCalendar.berlin()
    private let locale = Locale(identifier: "en_US")

    /// Finished days 08-10 to 08-15 total 600 tokens on six active days, a daily average of 100.
    private let claude = ["2026-08-10": 100, "2026-08-11": 50, "2026-08-12": 100, "2026-08-14": 90, "2026-08-15": 100, "2026-08-20": 500]
    private let codex = ["2026-08-11": 100, "2026-08-13": 60, "2026-08-22": 999, "2026-08-01": 7]

    private func series(
        _ scope: ReportScope, claude: [String: Int]? = nil, codex: [String: Int]? = nil, now: String = "2026-08-20"
    ) -> ReportDaySeries {
        ReportDaySeries.make(
            claude: claude ?? self.claude, codex: codex ?? self.codex, scope: scope,
            start: TestCalendar.date("2026-08-10"), end: TestCalendar.date("2026-08-23"),
            now: TestCalendar.date(now), calendar: calendar, locale: locale
        )
    }

    func testOneEntryPerCalendarDayWithBothProviders() {
        let days = series(.all).days

        XCTAssertEqual(days.count, 14)
        XCTAssertEqual(days.first?.key, "2026-08-10")
        XCTAssertEqual(days.last?.key, "2026-08-23")
        XCTAssertEqual(days[1].claude, 50)
        XCTAssertEqual(days[1].codex, 100)
        XCTAssertEqual(days[1].total, 150)
        XCTAssertEqual(days[6].total, 0)
        XCTAssertTrue(days[10].isToday)
        XCTAssertTrue(days[11].isFuture)
        XCTAssertFalse(days[10].isFuture)
    }

    func testScopeLeavesTheOtherProviderOut() {
        let claudeDays = series(.claude).days
        XCTAssertEqual(claudeDays[1].claude, 50)
        XCTAssertEqual(claudeDays[1].codex, 0)
        XCTAssertEqual(claudeDays[1].total, 50)

        let codexDays = series(.codex).days
        XCTAssertEqual(codexDays[1].claude, 0)
        XCTAssertEqual(codexDays[1].total, 100)
    }

    func testFiguresCountDaysUpToToday() {
        let all = series(.all)

        XCTAssertEqual(all.activeDays, 7)
        XCTAssertEqual(all.daysUpToToday, 11)
        XCTAssertEqual(all.longestStreak, 6)
        XCTAssertEqual(all.busiest?.key, "2026-08-20")
        XCTAssertEqual(all.busiest?.total, 500)

        let claudeOnly = series(.claude)
        XCTAssertEqual(claudeOnly.activeDays, 6)
        XCTAssertEqual(claudeOnly.longestStreak, 3)
    }

    func testBusiestDayIsTheLatestOnATie() {
        let tied = series(.claude, claude: ["2026-08-11": 200, "2026-08-14": 200])

        XCTAssertEqual(tied.busiest?.key, "2026-08-14")
    }

    func testDailyAverageCoversFinishedDaysWithUse() {
        XCTAssertEqual(series(.all).dailyAverage, 100)
    }

    func testFinishedDaysAFifthAwayCarryANote() {
        let notes = series(.all).days.map(\.note)

        XCTAssertEqual(notes[0], nil, "08-10 is the average")
        XCTAssertEqual(notes[1], "1.5\u{00D7} the daily average")
        XCTAssertEqual(notes[3], "60% of the daily average")
        XCTAssertEqual(notes[4], nil, "08-14 is only a tenth below")
        XCTAssertEqual(notes[6], nil, "an idle day carries no note")
        XCTAssertEqual(notes[10], nil, "today is not over")
        XCTAssertEqual(notes[12], nil, "a future day is not over")
    }

    func testFewerThanFiveDaysOfUseCompareNothing() {
        let sparse = series(.claude, claude: ["2026-08-10": 100, "2026-08-11": 300, "2026-08-12": 100, "2026-08-13": 100])

        XCTAssertNil(sparse.dailyAverage)
        XCTAssertEqual(sparse.days.compactMap(\.note), [])
    }

    func testAPastRangeHasNoToday() {
        let past = series(.all, now: "2026-09-02")

        XCTAssertEqual(past.days.filter(\.isToday).count, 0)
        XCTAssertEqual(past.daysUpToToday, 14)
        XCTAssertEqual(past.busiest?.key, "2026-08-22")
    }
}
