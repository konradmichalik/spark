@testable import Spark
import XCTest

final class CodexStatsRefreshTests: XCTestCase {
    private let now = Date()

    func testThePollKeepsBoundedPeriodsFresh() {
        for period in [StatsPeriod.today, .week, .month] {
            XCTAssertTrue(CodexStatsRefresh.shouldRefresh(period: period, trigger: .poll, lastRefresh: now, now: now))
        }
    }

    func testThePollNeverParsesEverythingForAllTime() {
        XCTAssertFalse(CodexStatsRefresh.shouldRefresh(period: .all, trigger: .poll, lastRefresh: nil, now: now))
        XCTAssertFalse(CodexStatsRefresh.shouldRefresh(period: .all, trigger: .poll, lastRefresh: now.addingTimeInterval(-9999), now: now))
    }

    func testOpeningTheScreenRefreshesAtMostEveryFiveMinutes() {
        func visit(ago: TimeInterval?) -> Bool {
            CodexStatsRefresh.shouldRefresh(period: .all, trigger: .visit, lastRefresh: ago.map { now.addingTimeInterval(-$0) }, now: now)
        }
        XCTAssertTrue(visit(ago: nil))
        XCTAssertFalse(visit(ago: 120))
        XCTAssertTrue(visit(ago: 301))
    }
}
