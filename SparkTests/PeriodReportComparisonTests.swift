@testable import Spark
import XCTest

final class PeriodReportComparisonTests: XCTestCase {
    private let calendar = TestCalendar.berlin()

    private func build(
        _ rollups: [String: DailyRollup], period: ReportPeriod = .week, offset: Int = 0, now: String = "2026-08-21"
    ) -> PeriodReport {
        PeriodReport.build(
            rollups: rollups, period: period, periodOffset: offset, now: TestCalendar.date(now, calendar: calendar), calendar: calendar
        )
    }

    private func dayString(_ value: Date) -> String {
        TranscriptCache.dayKey(for: value, calendar: calendar)
    }

    func testCurrentMonthComparesWithTheSameDaysOfTheMonthBefore() {
        let report = build([
            "2026-07-10": DailyRollup(sessionCount: 1, input: 40),
            "2026-07-20": DailyRollup(sessionCount: 1, input: 999), // after day 14, not part of the comparison
            "2026-08-10": DailyRollup(sessionCount: 1, input: 20)
        ], period: .month, now: "2026-08-15")

        XCTAssertEqual(report.previousPeriodTokens, 40)
        XCTAssertEqual(dayString(report.previousStart), "2026-07-01")
        XCTAssertEqual(dayString(report.previousEnd), "2026-07-14")
        XCTAssertEqual(report.trendPercent ?? .nan, -50, accuracy: 0.001)
        XCTAssertEqual(report.previousDayCount(calendar: calendar), 14)
        XCTAssertTrue(report.comparesPartOfMonth)
    }

    func testComparisonIncludesTodayOnceTodayHasClosed() {
        let report = build([
            "2026-07-15": DailyRollup(sessionCount: 1, input: 7),
            "2026-08-15": DailyRollup(sessionCount: 1, input: 5)
        ], period: .month, now: "2026-08-15")

        XCTAssertEqual(dayString(report.previousEnd), "2026-07-15")
        XCTAssertEqual(report.previousPeriodTokens, 7)
    }

    func testComparisonStopsAtTheLastDayOfAShorterPreviousMonth() {
        // March 1 to 30 against February, which only has 28 days.
        let report = build(["2026-02-28": DailyRollup(sessionCount: 1, input: 8)], period: .month, now: "2026-03-31")

        XCTAssertEqual(dayString(report.previousEnd), "2026-02-28")
        XCTAssertEqual(report.previousPeriodTokens, 8)
    }

    func testComparisonOfADayOneWindowIsEmpty() {
        let report = build(["2026-02-01": DailyRollup(sessionCount: 1, input: 8)], period: .month, now: "2026-03-01")

        XCTAssertTrue(report.previousEnd < report.previousStart)
        XCTAssertEqual(report.previousDayCount(calendar: calendar), 0)
        XCTAssertEqual(report.previousPeriodTokens, 0)
    }

    func testPastMonthStillComparesWithTheFullMonthBefore() {
        let report = build([
            "2026-06-30": DailyRollup(sessionCount: 1, input: 40),
            "2026-07-31": DailyRollup(sessionCount: 1, input: 20)
        ], period: .month, offset: 1, now: "2026-08-15")

        XCTAssertEqual(dayString(report.previousEnd), "2026-06-30")
        XCTAssertEqual(report.previousPeriodTokens, 40)
        XCTAssertFalse(report.comparesPartOfMonth)
    }

    func testWeekComparisonIsNotAPartialComparison() {
        XCTAssertFalse(build([:], period: .week).comparesPartOfMonth)
    }

    func testPreviousCacheHitRateCoversTheSameDaysAsTheComparison() {
        let report = build([
            "2026-07-05": DailyRollup(sessionCount: 1, cacheCreation: 10, cacheRead: 90),
            "2026-07-25": DailyRollup(sessionCount: 1, cacheCreation: 100, cacheRead: 0), // after day 14
            "2026-08-05": DailyRollup(sessionCount: 1, cacheCreation: 50, cacheRead: 50)
        ], period: .month, now: "2026-08-15")

        XCTAssertEqual(report.cacheHitRate ?? .nan, 0.5, accuracy: 0.001)
        XCTAssertEqual(report.previousCacheHitRate ?? .nan, 0.9, accuracy: 0.001)
    }

    func testPreviousCacheHitRateIsNilWithoutCacheActivity() {
        XCTAssertNil(build([:], period: .month).previousCacheHitRate)
    }
}
