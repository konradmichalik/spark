import XCTest
@testable import Spark

final class OverviewModelsTests: XCTestCase {
    func testForecastFromProjection() {
        XCTAssertEqual(SessionForecast(.safe(79)), SessionForecast(projected: 79, reachesLimit: false))
        XCTAssertEqual(SessionForecast(.limitReached(1800)), SessionForecast(projected: 100, reachesLimit: true))
        XCTAssertEqual(SessionForecast(.insufficientData), SessionForecast(projected: nil, reachesLimit: false))
    }

    func testForecastClampsAboveHundred() {
        XCTAssertEqual(SessionForecast(.safe(140)).projected, 100)
    }

    private func snapshot(_ minutesAgo: Double, session: Double, weekly: Double, now: Date) -> UsageSnapshot {
        UsageSnapshot(timestamp: now.addingTimeInterval(-minutesAgo * 60), sessionUtilization: session, weeklyUtilization: weekly)
    }

    func testColumnsTakeTheLatestSnapshotPerSlot() {
        let now = Date()
        let snapshots = [
            snapshot(359, session: 10, weekly: 40, now: now),
            snapshot(200, session: 30, weekly: 41, now: now),
            snapshot(1, session: 45, weekly: 48, now: now)
        ]
        let columns = HistoryColumns.make(snapshots, now: now, count: 6)
        XCTAssertEqual(columns.count, 6)
        XCTAssertEqual(columns.first?.session, 10)
        XCTAssertEqual(columns.first?.weekly, 40)
        XCTAssertEqual(columns.first?.time, now.addingTimeInterval(-359 * 60))
        XCTAssertEqual(columns.first?.slotStart, now.addingTimeInterval(-6 * 3600))
        XCTAssertEqual(columns.last?.session, 45)
        XCTAssertEqual(columns.last?.time, now.addingTimeInterval(-60))
    }

    func testEmptySlotsStayEmpty() {
        let now = Date()
        let columns = HistoryColumns.make([snapshot(1, session: 45, weekly: 48, now: now)], now: now, count: 6)
        XCTAssertEqual(columns.filter { $0.session == nil }.count, 5)
    }

    func testOldAndFutureSnapshotsAreIgnored() {
        let now = Date()
        let columns = HistoryColumns.make(
            [snapshot(400, session: 99, weekly: 99, now: now), snapshot(-5, session: 99, weekly: 99, now: now)],
            now: now, count: 6
        )
        XCTAssertTrue(columns.allSatisfy { $0.session == nil && $0.weekly == nil })
        XCTAssertTrue(HistoryColumns.make([], now: now, count: 0).isEmpty)
    }

    func testStatisticsValuePrefersCost() {
        XCTAssertEqual(OverviewSummary.statisticsValue(tokens: 2_500_000, messages: 130), "2.5M tokens")
        XCTAssertEqual(OverviewSummary.statisticsValue(tokens: 0, messages: 130), "130 messages")
        XCTAssertEqual(OverviewSummary.statisticsValue(tokens: nil, messages: 1), "1 message")
        XCTAssertNil(OverviewSummary.statisticsValue(tokens: nil, messages: nil))
    }

    func testLimitsValue() {
        XCTAssertEqual(OverviewSummary.moreLimitsValue(count: 2), "2 limits")
        XCTAssertEqual(OverviewSummary.moreLimitsValue(count: 1), "1 limit")
        XCTAssertNil(OverviewSummary.moreLimitsValue(count: 0))
    }

    func testScreenTitles() {
        XCTAssertEqual(PopoverScreen.history.title, "History")
        XCTAssertEqual(PopoverScreen.sessions.title, "Active sessions")
        XCTAssertEqual(PopoverScreen.statistics.title, "Statistics")
        XCTAssertEqual(PopoverScreen.limits.title, "More limits")
    }

    func testTabTooltip() {
        XCTAssertEqual(ProviderTabSummary.tooltip(plan: "Max 5x", signIn: "via Keychain"), "Max 5x · via Keychain")
        XCTAssertEqual(ProviderTabSummary.tooltip(plan: "Plus", signIn: nil), "Plus")
        XCTAssertNil(ProviderTabSummary.tooltip(plan: nil, signIn: ""))
    }

    func testCodexTabPlanWording() {
        XCTAssertEqual(ProviderTabSummary.codexPlan("Plus"), "ChatGPT Plus")
        XCTAssertNil(ProviderTabSummary.codexPlan(nil))
        XCTAssertNil(ProviderTabSummary.codexPlan(""))
    }

    func testFooterStatusText() {
        let now = Date()
        XCTAssertEqual(FooterText.status(isLoading: true, lastUpdated: nil, now: now), "Updating\u{2026}")
        XCTAssertEqual(FooterText.status(isLoading: false, lastUpdated: nil, now: now), "Not updated yet")
        XCTAssertEqual(FooterText.status(isLoading: false, lastUpdated: now.addingTimeInterval(-150), now: now), "Updated 2m ago")
    }

    func testFooterRelativeTime() {
        let now = Date()
        XCTAssertEqual(FooterText.relative(now.addingTimeInterval(-2), now: now), "just now")
        XCTAssertEqual(FooterText.relative(now.addingTimeInterval(-30), now: now), "30s ago")
        XCTAssertEqual(FooterText.relative(now.addingTimeInterval(-150), now: now), "2m ago")
        XCTAssertEqual(FooterText.relative(now.addingTimeInterval(-7300), now: now), "2h ago")
    }
}
