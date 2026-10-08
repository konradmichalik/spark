@testable import Spark
import XCTest

final class StatisticsAveragesTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    private func averages(_ period: StatsPeriod, messages: Int = 62, sessions: Int = 9, tokens: Int = 6_000_000) -> StatisticsAverages {
        StatisticsAverages(period: period, messages: messages, sessions: sessions, tokens: tokens, locale: english)
    }

    func testTodayAveragesPerSessionOnly() {
        let today = averages(.today)
        XCTAssertEqual(today.messages, "Average 6.9 messages per session")
        XCTAssertNil(today.sessions)
        XCTAssertEqual(today.tokens, "Average 666.7K tokens per session")
    }

    func testMultiDayPeriodsAlsoAveragePerDay() {
        let week = averages(.week, messages: 70, sessions: 14, tokens: 7_000_000)
        XCTAssertEqual(week.messages, "Average 5 messages per session")
        XCTAssertEqual(week.sessions, "Average 2 sessions per day")
        XCTAssertEqual(week.tokens, "Average 500.0K tokens per session\nAverage 1.0M tokens per day")
        XCTAssertEqual(averages(.month, sessions: 45).sessions, "Average 1.5 sessions per day")
    }

    func testAllTimeHasNoPerDayFigure() {
        let all = averages(.all)
        XCTAssertNil(all.sessions)
        XCTAssertEqual(all.tokens, "Average 666.7K tokens per session")
    }

    func testWithoutSessionsThereIsNothingToAverage() {
        let none = averages(.week, messages: 0, sessions: 0, tokens: 0)
        XCTAssertNil(none.messages)
        XCTAssertNil(none.sessions)
        XCTAssertNil(none.tokens)
    }

    func testSingularNouns() {
        XCTAssertEqual(averages(.today, messages: 1, sessions: 1).messages, "Average 1 message per session")
    }
}
