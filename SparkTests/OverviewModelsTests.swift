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
        XCTAssertEqual(columns.first, HistoryColumn(session: 10, weekly: 40))
        XCTAssertEqual(columns.last, HistoryColumn(session: 45, weekly: 48))
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
        XCTAssertEqual(OverviewSummary.statisticsValue(cost: 116.65, messages: 130), "≈ $117")
        XCTAssertEqual(OverviewSummary.statisticsValue(cost: 84.2, messages: 130), "≈ $84.20")
        XCTAssertEqual(OverviewSummary.statisticsValue(cost: 48_210, messages: nil), "≈ $48.2K")
        XCTAssertEqual(OverviewSummary.statisticsValue(cost: nil, messages: 130), "130 messages")
        XCTAssertEqual(OverviewSummary.statisticsValue(cost: nil, messages: 1), "1 message")
        XCTAssertNil(OverviewSummary.statisticsValue(cost: nil, messages: nil))
    }

    func testLimitsValue() {
        XCTAssertEqual(OverviewSummary.limitsValue(extraLimits: 2, plan: "Max 5x"), "2 more")
        XCTAssertEqual(OverviewSummary.limitsValue(extraLimits: 0, plan: "Plus"), "Plus")
        XCTAssertNil(OverviewSummary.limitsValue(extraLimits: 0, plan: nil))
    }

    func testScreenTitles() {
        XCTAssertEqual(PopoverScreen.history.title, "History")
        XCTAssertEqual(PopoverScreen.sessions.title, "Active sessions")
        XCTAssertEqual(PopoverScreen.statistics.title, "Statistics")
        XCTAssertEqual(PopoverScreen.limits.title, "All limits")
    }

    func testTabTooltip() {
        XCTAssertEqual(ProviderTabSummary.tooltip(plan: "Max 5x", signIn: "via Keychain"), "Max 5x · via Keychain")
        XCTAssertEqual(ProviderTabSummary.tooltip(plan: "Plus", signIn: nil), "Plus")
        XCTAssertNil(ProviderTabSummary.tooltip(plan: nil, signIn: ""))
    }

    func testFooterRelativeTime() {
        let now = Date()
        XCTAssertEqual(PopoverFooter.relative(now.addingTimeInterval(-2), now: now), "just now")
        XCTAssertEqual(PopoverFooter.relative(now.addingTimeInterval(-30), now: now), "30s ago")
        XCTAssertEqual(PopoverFooter.relative(now.addingTimeInterval(-150), now: now), "2m ago")
        XCTAssertEqual(PopoverFooter.relative(now.addingTimeInterval(-7300), now: now), "2h ago")
    }

    func testLimitWarningOnlyWhenTheLimitIsReached() {
        XCTAssertEqual(ForecastDetail.limitWarning(.limitReached(1200)), "Limit in ~20m")
        XCTAssertNil(ForecastDetail.limitWarning(.safe(79)))
        XCTAssertNil(ForecastDetail.limitWarning(.insufficientData))
    }

    func testForecastDetailLines() {
        XCTAssertEqual(
            ForecastDetail.text(projection: .safe(79), utilization: 45, secondsToReset: 2 * 3600, tokensPerMinute: 25_500),
            "~79% at reset, rising ~17%/h\n25.5K tokens per minute, last 15 min"
        )
        XCTAssertEqual(
            ForecastDetail.text(projection: .limitReached(1800), utilization: 90, secondsToReset: 3600, tokensPerMinute: nil),
            "Limit in ~30m, rising ~20%/h"
        )
        XCTAssertNil(ForecastDetail.text(projection: .insufficientData, utilization: 10, secondsToReset: nil, tokensPerMinute: nil))
    }
}
