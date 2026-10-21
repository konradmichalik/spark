import XCTest
@testable import Spark

final class CodexBurnRateRefreshTests: XCTestCase {
    func testVisibleOverviewRefreshesEveryMinute() {
        let now = Date()
        XCTAssertTrue(CodexBurnRateRefresh.shouldRefresh(lastRefresh: nil, now: now))
        XCTAssertFalse(CodexBurnRateRefresh.shouldRefresh(lastRefresh: now.addingTimeInterval(-59), now: now))
        XCTAssertTrue(CodexBurnRateRefresh.shouldRefresh(lastRefresh: now.addingTimeInterval(-60), now: now))
    }

    func testOnlyTheLatestActiveScanCanPublishItsResult() {
        let older = UUID()
        let latest = UUID()

        XCTAssertFalse(CodexBurnRateRefresh.canPublish(scanID: older, currentScanID: latest, isActive: true))
        XCTAssertFalse(CodexBurnRateRefresh.canPublish(scanID: latest, currentScanID: latest, isActive: false))
        XCTAssertTrue(CodexBurnRateRefresh.canPublish(scanID: latest, currentScanID: latest, isActive: true))
    }
}
