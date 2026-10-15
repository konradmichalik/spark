@testable import Spark
import XCTest

final class WeekdayProfileTests: XCTestCase {
    private let calendar = TestCalendar.berlin(firstWeekday: 2)
    private let english = Locale(identifier: "en_US")

    private func date(_ day: String) -> Date { TestCalendar.date(day, calendar: calendar) }

    private func profile(_ tokens: [String: Int], _ start: String = "2026-09-01", _ end: String = "2026-09-30") -> WeekdayProfile? {
        WeekdayProfile.make(dayTokens: tokens, start: date(start), end: date(end), calendar: calendar, locale: english)
    }

    func testEachWeekdayAveragesOverEveryOccurrenceIncludingIdleOnes() {
        // September 2026 has four Mondays (7, 14, 21, 28) and five Tuesdays (1, 8, 15, 22, 29).
        let tokens = ["2026-09-07": 400, "2026-09-14": 400, "2026-09-01": 500]
        let result = profile(tokens)
        XCTAssertEqual(result?.entries.first?.name, "Mon")
        XCTAssertEqual(result?.entries.first?.average, 200)
        XCTAssertEqual(result?.entries.first?.occurrences, 4)
        XCTAssertEqual(result?.entries[1].average, 100)
        XCTAssertEqual(result?.entries[1].occurrences, 5)
    }

    func testShareIsRelativeToTheBusiestWeekday() {
        let result = profile(["2026-09-07": 400, "2026-09-14": 400, "2026-09-01": 500])
        XCTAssertEqual(result?.entries[0].share ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(result?.entries[1].share ?? 0, 50, accuracy: 0.001)
        XCTAssertEqual(result?.entries[2].share ?? -1, 0, accuracy: 0.001)
    }

    func testEntriesStartOnTheCalendarsFirstWeekday() {
        let sunday = TestCalendar.berlin(firstWeekday: 1)
        let result = WeekdayProfile.make(
            dayTokens: ["2026-09-06": 10], start: date("2026-09-01"), end: date("2026-09-30"), calendar: sunday, locale: english
        )
        XCTAssertEqual(result?.entries.map(\.name), ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
    }

    func testAShortPeriodHasNoProfile() {
        XCTAssertNil(profile(["2026-09-07": 400], "2026-09-01", "2026-09-13"))
        XCTAssertNotNil(profile(["2026-09-07": 400], "2026-09-01", "2026-09-14"))
    }

    func testWithoutUseThereIsNoProfile() {
        XCTAssertNil(profile([:]))
    }

    func testDaysOutsideThePeriodAreIgnored() {
        let result = profile(["2026-08-31": 9_999, "2026-10-01": 9_999, "2026-09-07": 400])
        XCTAssertEqual(result?.entries.first?.average, 100)
        XCTAssertEqual(result?.entries[2].average, 0)
    }

    func testTooltipNamesTheAverageAndTheSampleSize() {
        let result = profile(["2026-09-07": 4_000, "2026-09-14": 4_000])
        XCTAssertEqual(result?.entries.first?.tooltip, "Average 2.0K tokens, from 4 days")
    }
}
