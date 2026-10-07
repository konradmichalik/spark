@testable import Spark
import XCTest

final class ServiceStatusTests: XCTestCase {
    func testOnlyReportedProblemsAreIncidents() {
        XCTAssertFalse(ClaudeServiceStatus.operational.isIncident)
        XCTAssertFalse(ClaudeServiceStatus.none.isIncident)
        XCTAssertFalse(ClaudeServiceStatus.unknown.isIncident)
        XCTAssertTrue(ClaudeServiceStatus.degradedPerformance.isIncident)
        XCTAssertTrue(ClaudeServiceStatus.partialOutage.isIncident)
        XCTAssertTrue(ClaudeServiceStatus.majorOutage.isIncident)
    }
}
