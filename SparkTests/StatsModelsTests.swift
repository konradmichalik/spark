import XCTest
@testable import Spark

final class StatsModelsTests: XCTestCase {

    // MARK: - StatsPeriod.startDate

    func testTodayStartsAtStartOfDay() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        XCTAssertEqual(StatsPeriod.today.startDate, startOfDay)
    }

    func testWeekStartsSevenDaysAgo() {
        guard let startDate = StatsPeriod.week.startDate else {
            return XCTFail("week period should have a start date")
        }
        let expected = Date().addingTimeInterval(-7 * 24 * 3600)
        XCTAssertEqual(startDate.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
    }

    func testMonthStartsThirtyDaysAgo() {
        guard let startDate = StatsPeriod.month.startDate else {
            return XCTFail("month period should have a start date")
        }
        let expected = Date().addingTimeInterval(-30 * 24 * 3600)
        XCTAssertEqual(startDate.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
    }

    func testAllHasNoStartDate() {
        XCTAssertNil(StatsPeriod.all.startDate)
    }

    // MARK: - LiveStats

    func testTotalTokensSumsInputAndOutput() {
        let stats = LiveStats(period: .today, messageCount: 5, sessionCount: 1, inputTokens: 100, outputTokens: 50)
        XCTAssertEqual(stats.totalTokens, 150)
    }

    func testFormattedTokensUsesCompactNotation() {
        let stats = LiveStats(period: .all, messageCount: 1, sessionCount: 1, inputTokens: 1_200_000, outputTokens: 0)
        XCTAssertEqual(stats.formattedTokens, "1.2M")
    }
}
