@testable import Spark
import XCTest

final class AverageComparisonTests: XCTestCase {
    private let calendar = TestCalendar.berlin()
    private let english = Locale(identifier: "en_US")

    private func rollups(_ tokens: [String: Int]) -> [String: DailyRollup] {
        tokens.mapValues { DailyRollup(sessionCount: 1, input: $0) }
    }

    private func typical(_ tokens: [String: Int], today: String = "2026-10-15") -> Int? {
        AverageComparison.typicalDay(rollups: rollups(tokens), before: TestCalendar.date(today, calendar: calendar), calendar: calendar)
    }

    // MARK: - Typical day

    func testTypicalDayIsTheMedianOfTheDaysWithUse() {
        // One huge day would lift a mean to 220; the median stays with the ordinary ones.
        let tokens = ["2026-10-14": 100, "2026-10-13": 120, "2026-10-12": 110, "2026-10-11": 90, "2026-10-10": 680]
        XCTAssertEqual(typical(tokens), 110)
    }

    func testAnEvenCountAveragesTheTwoMiddleDays() {
        let tokens = [
            "2026-10-14": 100, "2026-10-13": 200, "2026-10-12": 300, "2026-10-11": 400, "2026-10-10": 500, "2026-10-09": 600
        ]
        XCTAssertEqual(typical(tokens), 350)
    }

    func testIdleDaysAreNoTypicalDay() {
        let tokens = ["2026-10-14": 100, "2026-10-13": 100, "2026-10-12": 100, "2026-10-11": 100, "2026-10-10": 100, "2026-10-09": 0]
        XCTAssertEqual(typical(tokens), 100)
    }

    func testTooFewDaysOfUseGiveNoTypicalDay() {
        let tokens = ["2026-10-14": 100, "2026-10-13": 100, "2026-10-12": 100, "2026-10-11": 100]
        XCTAssertNil(typical(tokens))
    }

    func testOnlyTheLastTwentyEightDaysCountAndTodayDoesNot() {
        var tokens = ["2026-10-15": 9_999, "2026-09-16": 9_999] // today, and the 29th day back
        for day in 10...14 { tokens["2026-10-\(day)"] = 100 }
        XCTAssertEqual(typical(tokens), 100)
        XCTAssertEqual(typical(["2026-09-17": 100, "2026-09-18": 100, "2026-09-19": 100, "2026-09-20": 100, "2026-09-21": 100]), 100)
    }

    // MARK: - Wording

    func testTodayIsAShareOfATypicalDay() {
        XCTAssertEqual(AverageComparison.todayText(tokens: 400, typical: 1_000, locale: english), "40% of a typical day")
        XCTAssertEqual(AverageComparison.todayText(tokens: 1_500, typical: 1_000, locale: english), "150% of a typical day")
    }

    func testADayWellAboveTheAverageIsAMultiple() {
        XCTAssertEqual(AverageComparison.dayNote(tokens: 1_400, average: 1_000, locale: english), "1.4\u{00D7} the daily average")
        XCTAssertEqual(AverageComparison.dayNote(tokens: 1_200, average: 1_000, locale: english), "1.2\u{00D7} the daily average")
    }

    func testADayWellBelowTheAverageIsAShare() {
        XCTAssertEqual(AverageComparison.dayNote(tokens: 600, average: 1_000, locale: english), "60% of the daily average")
        XCTAssertEqual(AverageComparison.dayNote(tokens: 800, average: 1_000, locale: english), "80% of the daily average")
    }

    func testADayCloseToTheAverageHasNoNote() {
        XCTAssertNil(AverageComparison.dayNote(tokens: 1_199, average: 1_000, locale: english))
        XCTAssertNil(AverageComparison.dayNote(tokens: 801, average: 1_000, locale: english))
        XCTAssertNil(AverageComparison.dayNote(tokens: 500, average: 0, locale: english))
    }

    // MARK: - Today hint

    func testTodayHintSetsTodayAgainstTheTypicalDay() {
        let days = rollups(["2026-10-14": 1_000, "2026-10-13": 1_000, "2026-10-12": 1_000, "2026-10-11": 1_000, "2026-10-10": 1_000])
        let hint = AverageComparison.todayHint(
            tokens: 250, rollups: days, now: TestCalendar.date("2026-10-15", calendar: calendar), calendar: calendar, locale: english
        )
        XCTAssertEqual(hint?.text, "25% of a typical day")
        XCTAssertTrue(hint?.tooltip.hasPrefix("A typical day is 1.0K tokens") ?? false)
    }

    func testTodayHintIsMissingWithoutUseOrHistory() {
        let days = rollups(["2026-10-14": 1_000, "2026-10-13": 1_000, "2026-10-12": 1_000, "2026-10-11": 1_000, "2026-10-10": 1_000])
        let now = TestCalendar.date("2026-10-15", calendar: calendar)
        XCTAssertNil(AverageComparison.todayHint(tokens: 0, rollups: days, now: now, calendar: calendar))
        XCTAssertNil(AverageComparison.todayHint(tokens: 250, rollups: [:], now: now, calendar: calendar))
    }
}
