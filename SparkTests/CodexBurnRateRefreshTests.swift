import XCTest
@testable import Spark

final class CodexBurnRateRefreshTests: XCTestCase {
    func testVisibleOverviewRefreshesEveryMinute() {
        let now = Date()
        XCTAssertTrue(CodexBurnRateRefresh.shouldRefresh(lastRefresh: nil, now: now))
        XCTAssertFalse(CodexBurnRateRefresh.shouldRefresh(lastRefresh: now.addingTimeInterval(-59), now: now))
        XCTAssertTrue(CodexBurnRateRefresh.shouldRefresh(lastRefresh: now.addingTimeInterval(-60), now: now))
    }

    func testTheFourteenDayBaselineRescansOnlyEverySixHours() {
        let now = Date()
        let interval = CodexBurnRateRefresh.baselineInterval

        XCTAssertEqual(interval, 6 * 60 * 60)
        XCTAssertTrue(CodexBurnRateRefresh.shouldRefresh(lastRefresh: nil, now: now, interval: interval))
        XCTAssertFalse(CodexBurnRateRefresh.shouldRefresh(lastRefresh: now.addingTimeInterval(-interval + 1), now: now, interval: interval))
        XCTAssertTrue(CodexBurnRateRefresh.shouldRefresh(lastRefresh: now.addingTimeInterval(-interval), now: now, interval: interval))
    }

    func testOnlyTheLatestActiveScanCanPublishItsResult() {
        let older = UUID()
        let latest = UUID()

        XCTAssertFalse(CodexBurnRateRefresh.canPublish(scanID: older, currentScanID: latest, isActive: true))
        XCTAssertFalse(CodexBurnRateRefresh.canPublish(scanID: latest, currentScanID: latest, isActive: false))
        XCTAssertTrue(CodexBurnRateRefresh.canPublish(scanID: latest, currentScanID: latest, isActive: true))
    }
}
