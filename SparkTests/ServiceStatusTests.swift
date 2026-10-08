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

final class ServiceStatusParsingTests: XCTestCase {
    func testOverallIndicatorMapsToIncidents() {
        XCTAssertEqual(ClaudeServiceStatus.parse("none"), .none)
        XCTAssertEqual(ClaudeServiceStatus.parse("minor"), .degradedPerformance)
        XCTAssertEqual(ClaudeServiceStatus.parse("major"), .partialOutage)
        XCTAssertEqual(ClaudeServiceStatus.parse("critical"), .majorOutage)
        XCTAssertTrue(ClaudeServiceStatus.parse("minor").isIncident)
    }

    func testComponentStatusesStillParse() {
        XCTAssertEqual(ClaudeServiceStatus.parse("operational"), .operational)
        XCTAssertEqual(ClaudeServiceStatus.parse("degraded_performance"), .degradedPerformance)
        XCTAssertEqual(ClaudeServiceStatus.parse("partial_outage"), .partialOutage)
        XCTAssertEqual(ClaudeServiceStatus.parse("major_outage"), .majorOutage)
    }

    func testMaintenanceCountsAsDegradedAndUnknownStaysUnknown() {
        XCTAssertEqual(ClaudeServiceStatus.parse("under_maintenance"), .degradedPerformance)
        XCTAssertEqual(ClaudeServiceStatus.parse("maintenance"), .degradedPerformance)
        XCTAssertEqual(ClaudeServiceStatus.parse("something_new"), .unknown)
    }
}

final class ServiceStatusNotificationTests: XCTestCase {
    func testOnlyIncidentsNotify() {
        XCTAssertTrue(ClaudeServiceStatus.shouldNotify(enabled: true, current: .majorOutage, last: .operational))
        XCTAssertTrue(ClaudeServiceStatus.shouldNotify(enabled: true, current: .degradedPerformance, last: .unknown))
        XCTAssertFalse(ClaudeServiceStatus.shouldNotify(enabled: true, current: .unknown, last: .operational), "no network is no outage")
        XCTAssertFalse(ClaudeServiceStatus.shouldNotify(enabled: true, current: .operational, last: .majorOutage))
        XCTAssertFalse(ClaudeServiceStatus.shouldNotify(enabled: true, current: .majorOutage, last: .majorOutage))
        XCTAssertFalse(ClaudeServiceStatus.shouldNotify(enabled: false, current: .majorOutage, last: .operational))
    }

    func testFailedFetchLeavesNoOldIncidentBehind() {
        let snapshot = ServiceStatusSnapshot.unavailable
        XCTAssertEqual([snapshot.overall, snapshot.claudeCode, snapshot.api], [.unknown, .unknown, .unknown])
        XCTAssertEqual(snapshot.description, "Status unavailable")
    }
}
