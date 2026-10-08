@testable import Spark
import XCTest

final class StatisticsAveragesTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    private func averages(
        activeDays: Int, messages: Int = 62, sessions: Int = 9, tokens: Int = 6_000_000
    ) -> StatisticsAverages {
        StatisticsAverages(activeDays: activeDays, messages: messages, sessions: sessions, tokens: tokens, locale: english)
    }

    func testOneActiveDayAveragesPerSessionOnly() {
        let today = averages(activeDays: 1)
        XCTAssertEqual(today.messages, "Average 6.9 messages per session")
        XCTAssertNil(today.sessions)
        XCTAssertEqual(today.tokens, "Average 666.7K tokens per session")
    }

    func testSeveralActiveDaysAlsoAveragePerActiveDay() {
        let week = averages(activeDays: 4, messages: 70, sessions: 14, tokens: 8_000_000)
        XCTAssertEqual(week.messages, "Average 5 messages per session")
        XCTAssertEqual(week.sessions, "Average 3.5 sessions per active day")
        XCTAssertEqual(week.tokens, "Average 571.4K tokens per session\nAverage 2.0M tokens per active day")
    }

    func testIdleDaysDoNotLowerTheAverage() {
        // Seven days in the period, but only two with tokens: the divisor is two.
        XCTAssertEqual(averages(activeDays: 2, sessions: 10).sessions, "Average 5 sessions per active day")
    }

    func testWithoutSessionsOrActiveDaysThereIsNothingToAverage() {
        let none = averages(activeDays: 0, messages: 0, sessions: 0, tokens: 0)
        XCTAssertNil(none.messages)
        XCTAssertNil(none.sessions)
        XCTAssertNil(none.tokens)
        XCTAssertNil(averages(activeDays: 0).sessions)
    }

    func testSingularNouns() {
        XCTAssertEqual(averages(activeDays: 1, messages: 1, sessions: 1).messages, "Average 1 message per session")
        XCTAssertEqual(averages(activeDays: 3, sessions: 3).sessions, "Average 1 session per active day")
    }
}
