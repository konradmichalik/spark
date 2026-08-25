import XCTest
@testable import Spark

final class WeeklyReportTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func date(_ day: String, time: String = "12:00") -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        // swiftlint:disable:next force_unwrapping
        return formatter.date(from: "\(day) \(time)")!
    }

    private func build(
        _ rollups: [String: DailyRollup],
        modelTotals: [String: Int] = [:],
        topProjects: [ProjectUsage] = [],
        now: String = "2026-08-21"
    ) -> WeeklyReport {
        WeeklyReport.build(
            rollups: rollups,
            modelTotals: modelTotals,
            topProjects: topProjects,
            now: date(now),
            calendar: calendar
        )
    }

    private func windowStart(_ rollups: [String: DailyRollup], now: String = "2026-08-21") -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: WeeklyReport.windowStart(rollups: rollups, now: date(now), calendar: calendar))
    }

    // MARK: - Window boundaries

    func testCurrentWeekSumsTheSevenMostRecentClosedDays() {
        let report = build([
            "2026-08-13": DailyRollup(sessionCount: 1, input: 999), // outside the window (previous week)
            "2026-08-15": DailyRollup(sessionCount: 1, input: 10),
            "2026-08-20": DailyRollup(sessionCount: 1, input: 20)
        ])

        XCTAssertEqual(report.currentWeekTokens, 30)
    }

    func testCurrentWeekIncludesTheOldestDayOfTheSevenDayWindow() {
        // 2026-08-14 is exactly 6 days before the window's last day (2026-08-20) — the far edge
        // of the current window, not yet the previous week.
        let report = build(["2026-08-14": DailyRollup(sessionCount: 1, input: 5)])

        XCTAssertEqual(report.currentWeekTokens, 5)
    }

    func testPreviousWeekSumsTheSevenDaysBeforeThat() {
        let report = build([
            "2026-08-08": DailyRollup(sessionCount: 1, input: 40),
            "2026-08-20": DailyRollup(sessionCount: 1, input: 20)
        ])

        XCTAssertEqual(report.previousWeekTokens, 40)
    }

    /// Mirrors `VolumeDaySeries`: today carries no rollup until it closes, so the window ends on
    /// the last closed day unless today already has a rollup.
    func testWindowEndsYesterdayUnlessTodayHasARollup() {
        let withoutToday = build(["2026-08-20": DailyRollup(sessionCount: 1, input: 20)])
        XCTAssertEqual(withoutToday.currentWeekTokens, 20)

        let withToday = build(["2026-08-21": DailyRollup(sessionCount: 1, input: 20)])
        XCTAssertEqual(withToday.currentWeekTokens, 20)
    }

    func testWindowStartAlignsWithTheFirstDayOfTheCurrentWindow() {
        XCTAssertEqual(windowStart(["2026-08-20": DailyRollup(sessionCount: 1, input: 20)]), "2026-08-14")
        XCTAssertEqual(windowStart(["2026-08-21": DailyRollup(sessionCount: 1, input: 20)]), "2026-08-15")
    }

    // MARK: - Real tokens (cache reads excluded)

    func testWeeklyTotalsExcludeCacheReads() {
        let report = build([
            "2026-08-20": DailyRollup(sessionCount: 1, input: 10, output: 5, cacheCreation: 2, cacheRead: 1_000)
        ])

        XCTAssertEqual(report.currentWeekTokens, 17)
    }

    // MARK: - Trend

    func testTrendPercentIsNilWhenPreviousWeekHasNoRollupsAtAll() {
        let report = build(["2026-08-20": DailyRollup(sessionCount: 1, input: 20)])

        XCTAssertNil(report.trendPercent)
    }

    func testTrendPercentIsNilWhenPreviousWeekRollupsSumToZero() {
        let report = build([
            "2026-08-08": DailyRollup(sessionCount: 1), // a real, closed day with zero tokens
            "2026-08-20": DailyRollup(sessionCount: 1, input: 20)
        ])

        XCTAssertNil(report.trendPercent)
    }

    func testTrendPercentIsZeroWhenBothWeeksMatch() {
        let report = build([
            "2026-08-08": DailyRollup(sessionCount: 1, input: 100),
            "2026-08-20": DailyRollup(sessionCount: 1, input: 100)
        ])

        XCTAssertEqual(report.trendPercent ?? .nan, 0, accuracy: 0.001)
    }

    func testTrendPercentIsPositiveWhenCurrentWeekIsHigher() {
        let report = build([
            "2026-08-08": DailyRollup(sessionCount: 1, input: 100), // previous week
            "2026-08-20": DailyRollup(sessionCount: 1, input: 150) // current week
        ])

        XCTAssertEqual(report.trendPercent ?? .nan, 50, accuracy: 0.001)
    }

    func testTrendPercentIsNegativeWhenCurrentWeekIsLower() {
        let report = build([
            "2026-08-08": DailyRollup(sessionCount: 1, input: 200), // previous week
            "2026-08-20": DailyRollup(sessionCount: 1, input: 50) // current week
        ])

        XCTAssertEqual(report.trendPercent ?? .nan, -75, accuracy: 0.001)
    }

    // MARK: - Caller-supplied model totals / top projects

    func testModelTotalsPassThroughUnchanged() {
        let report = build([:], modelTotals: ["claude-sonnet-4-6": 15])

        XCTAssertEqual(report.modelTotals["claude-sonnet-4-6"], 15)
    }

    func testTopProjectsPassThroughUnchanged() {
        let projects = [ProjectUsage(key: "-Users-me-app", displayName: "app", tokens: 42)]
        let report = build([:], topProjects: projects)

        XCTAssertEqual(report.topProjects.map(\.key), ["-Users-me-app"])
    }

    // MARK: - hasData

    func testHasDataIsFalseWhenNothingWasFound() {
        let report = build([:])

        XCTAssertFalse(report.hasData)
    }

    func testHasDataIsTrueWhenOnlyTopProjectsAreNonEmpty() {
        let report = build([:], topProjects: [ProjectUsage(key: "-Users-me-app", displayName: "app", tokens: 1)])

        XCTAssertTrue(report.hasData)
    }
}
