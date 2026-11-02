@testable import Spark
import XCTest

final class ReportLimitsTests: XCTestCase {
    private let calendar = TestCalendar.berlin()
    private let locale = Locale(identifier: "en_US")

    private func snapshot(_ day: String, time: String = "12:00", session: Double, weekly: Double) -> UsageSnapshot {
        UsageSnapshot(timestamp: TestCalendar.date(day, time: time, calendar: calendar), sessionUtilization: session, weeklyUtilization: weekly)
    }

    private func limits(_ snapshots: [UsageSnapshot], provider: ReportProvider = .claude, isCurrentPeriod: Bool = false) -> ReportLimits {
        ReportLimits.make(
            provider: provider, snapshots: snapshots, start: TestCalendar.date("2026-08-10"), end: TestCalendar.date("2026-08-13"),
            isCurrentPeriod: isCurrentPeriod, calendar: calendar, locale: locale
        )
    }

    private let atLimitTwice = [
        UsageSnapshot(timestamp: TestCalendar.date("2026-08-10", time: "10:00"), sessionUtilization: 40, weeklyUtilization: 20),
        UsageSnapshot(timestamp: TestCalendar.date("2026-08-10", time: "15:00"), sessionUtilization: 100, weeklyUtilization: 35),
        UsageSnapshot(timestamp: TestCalendar.date("2026-08-11"), sessionUtilization: 100, weeklyUtilization: 60),
        UsageSnapshot(timestamp: TestCalendar.date("2026-08-12"), sessionUtilization: 80, weeklyUtilization: 100)
    ]

    func testOneDayPerCalendarDayWithItsPeaks() {
        let result = limits(atLimitTwice, provider: .codex)

        XCTAssertEqual(result.provider, .codex)
        XCTAssertEqual(result.days.count, 4)
        XCTAssertEqual(result.days.map(\.sessionUtilization), [100, 100, 80, nil])
        XCTAssertEqual(result.days.map(\.weeklyUtilization), [35, 60, 100, nil])
    }

    func testFiguresOfTheRange() {
        let result = limits(atLimitTwice)

        XCTAssertTrue(result.hasHistory)
        XCTAssertEqual(result.weekMax, 100)
        XCTAssertEqual(result.daysAtLimit, 2)
    }

    func testSummariesCountTheDaysAtTheSessionLimit() {
        let result = limits(atLimitTwice)

        XCTAssertEqual(result.summary, "up to 100% \u{00B7} 2\u{00D7} at limit")
        XCTAssertEqual(result.longSummary, "Week up to 100% \u{00B7} 2 days at the session limit")
    }

    func testOneDayAtTheLimitIsSingular() {
        let result = limits([snapshot("2026-08-11", session: 100, weekly: 35)])

        XCTAssertEqual(result.summary, "up to 35% \u{00B7} 1\u{00D7} at limit")
        XCTAssertEqual(result.longSummary, "Week up to 35% \u{00B7} 1 day at the session limit")
    }

    func testNeverAtTheLimit() {
        let result = limits([snapshot("2026-08-11", session: 99.6, weekly: 35)])

        XCTAssertEqual(result.daysAtLimit, 0)
        XCTAssertEqual(result.summary, "up to 35% \u{00B7} never at limit")
        XCTAssertEqual(result.longSummary, "Week up to 35% \u{00B7} Session limit never reached")
    }

    func testNoSnapshotInTheRangeMeansNoHistory() {
        let result = limits([snapshot("2026-08-20", session: 100, weekly: 90)])

        XCTAssertFalse(result.hasHistory)
        XCTAssertNil(result.weekMax)
        XCTAssertEqual(result.daysAtLimit, 0)
        XCTAssertEqual(result.summary, "No limit history for that period.")
        XCTAssertEqual(result.longSummary, "No limit history for that period.")
    }

    func testTheCurrentPeriodWithoutSnapshotsWaitsForData() {
        let result = limits([], isCurrentPeriod: true)

        XCTAssertFalse(result.hasHistory)
        XCTAssertEqual(result.summary, "Not enough data yet.")
        XCTAssertEqual(result.longSummary, "Not enough data yet.")
    }

    func testWithoutAWeeklyWindowOnlyTheSessionPartIsSaid() {
        let noWeek = UsageSnapshot(
            timestamp: TestCalendar.date("2026-08-11"), sessionUtilization: 100, weeklyUtilization: 0,
            sessionMissing: false, weeklyMissing: true
        )
        let result = limits([noWeek])

        XCTAssertNil(result.weekMax)
        XCTAssertEqual(result.summary, "1\u{00D7} at limit")
        XCTAssertEqual(result.longSummary, "1 day at the session limit")
    }
}
