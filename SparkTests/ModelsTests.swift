import XCTest
@testable import Spark

final class ModelsTests: XCTestCase {

    // MARK: - UsageAPIResponse Decoding

    func testDecodeUsageAPIResponse() throws {
        let json = """
        {
            "five_hour": { "utilization": 42.5, "resets_at": "2026-03-30T18:00:00Z" },
            "seven_day": { "utilization": 65.0, "resets_at": "2026-04-05T00:00:00Z" },
            "seven_day_sonnet": { "utilization": 30.0, "resets_at": "2026-04-05T00:00:00Z" }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageAPIResponse.self, from: json)
        XCTAssertEqual(response.fiveHour?.utilization, 42.5)
        XCTAssertEqual(response.sevenDay?.utilization, 65.0)
        XCTAssertEqual(response.sevenDaySonnet?.utilization, 30.0)
        XCTAssertNotNil(response.fiveHour?.resetsAt)
    }

    func testDecodeUsageAPIResponsePartial() throws {
        let json = """
        {
            "five_hour": { "utilization": 10.0 }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageAPIResponse.self, from: json)
        XCTAssertEqual(response.fiveHour?.utilization, 10.0)
        XCTAssertNil(response.fiveHour?.resetsAt)
        XCTAssertNil(response.sevenDay)
        XCTAssertNil(response.sevenDaySonnet)
    }

    // MARK: - UsageBucket

    func testResetsAtDateParsing() throws {
        let json = """
        { "utilization": 50.0, "resets_at": "2026-03-30T18:30:00Z" }
        """.data(using: .utf8)!

        let bucket = try JSONDecoder().decode(UsageBucket.self, from: json)
        XCTAssertNotNil(bucket.resetsAtDate)
    }

    func testResetsAtDateWithFractionalSeconds() throws {
        let json = """
        { "utilization": 50.0, "resets_at": "2026-03-30T18:30:00.123Z" }
        """.data(using: .utf8)!

        let bucket = try JSONDecoder().decode(UsageBucket.self, from: json)
        XCTAssertNotNil(bucket.resetsAtDate)
    }

    func testResetsAtDateNil() throws {
        let json = """
        { "utilization": 50.0 }
        """.data(using: .utf8)!

        let bucket = try JSONDecoder().decode(UsageBucket.self, from: json)
        XCTAssertNil(bucket.resetsAtDate)
        XCTAssertNil(bucket.timeUntilReset)
    }

    // MARK: - UsageData

    func testUsageDataEmpty() {
        let data = UsageData.empty
        XCTAssertEqual(data.sessionUtilization, 0)
        XCTAssertEqual(data.weeklyUtilization, 0)
        XCTAssertEqual(data.maxUtilization, 0)
    }

    func testUsageDataMaxUtilization() throws {
        let json = """
        { "utilization": 80.0 }
        """.data(using: .utf8)!
        let session = try JSONDecoder().decode(UsageBucket.self, from: json)

        let json2 = """
        { "utilization": 40.0 }
        """.data(using: .utf8)!
        let weekly = try JSONDecoder().decode(UsageBucket.self, from: json2)

        let data = UsageData(session: session, weekly: weekly)
        XCTAssertEqual(data.sessionUtilization, 80.0)
        XCTAssertEqual(data.weeklyUtilization, 40.0)
        XCTAssertEqual(data.maxUtilization, 80.0)
    }

    // MARK: - ClaudeServiceStatus

    func testStatusDecoding() throws {
        let json = "\"operational\"".data(using: .utf8)!
        let status = try JSONDecoder().decode(ClaudeServiceStatus.self, from: json)
        XCTAssertEqual(status, .operational)
        XCTAssertTrue(status.isHealthy)
    }

    func testStatusNoneIsHealthy() throws {
        let json = "\"none\"".data(using: .utf8)!
        let status = try JSONDecoder().decode(ClaudeServiceStatus.self, from: json)
        XCTAssertEqual(status, .none)
        XCTAssertTrue(status.isHealthy)
    }

    func testStatusMajorOutage() throws {
        let json = "\"major_outage\"".data(using: .utf8)!
        let status = try JSONDecoder().decode(ClaudeServiceStatus.self, from: json)
        XCTAssertEqual(status, .majorOutage)
        XCTAssertFalse(status.isHealthy)
        XCTAssertEqual(status.displayName, "Major Outage")
    }

    func testStatusDisplayNames() {
        XCTAssertEqual(ClaudeServiceStatus.operational.displayName, "Operational")
        XCTAssertEqual(ClaudeServiceStatus.degradedPerformance.displayName, "Degraded")
        XCTAssertEqual(ClaudeServiceStatus.partialOutage.displayName, "Partial Outage")
        XCTAssertEqual(ClaudeServiceStatus.unknown.displayName, "Unknown")
    }

    // MARK: - StatusPageResponse

    func testDecodeStatusPageResponse() throws {
        let json = """
        {
            "status": { "indicator": "none", "description": "All Systems Operational" },
            "components": [
                { "name": "API", "status": "operational" },
                { "name": "Claude.ai", "status": "operational" }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(StatusPageResponse.self, from: json)
        XCTAssertEqual(response.status.indicator, "none")
        XCTAssertEqual(response.status.description, "All Systems Operational")
        XCTAssertEqual(response.components?.count, 2)
    }

    // MARK: - UsageSnapshot

    func testUsageSnapshotCodable() throws {
        let snapshot = UsageSnapshot(sessionUtilization: 42.0, weeklyUtilization: 65.0)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)

        XCTAssertEqual(decoded.sessionUtilization, 42.0)
        XCTAssertEqual(decoded.weeklyUtilization, 65.0)
        XCTAssertEqual(decoded.id, snapshot.id)
    }

    // MARK: - SessionProjection

    func testProjectionLimitReached() {
        let now = Date()
        let history = [
            UsageSnapshot(timestamp: now.addingTimeInterval(-3000), sessionUtilization: 50.0, weeklyUtilization: 0),
            UsageSnapshot(timestamp: now.addingTimeInterval(-600), sessionUtilization: 70.0, weeklyUtilization: 0),
            UsageSnapshot(timestamp: now, sessionUtilization: 80.0, weeklyUtilization: 0)
        ]
        // Rate: 30% per ~50min ≈ 36%/h. At 80% with 2h to reset → 80 + 72 = 152% → limit reached
        let resetsAt = now.addingTimeInterval(7200) // 2 hours
        let result = SessionProjection.calculate(history: history, currentUtilization: 80.0, resetsAt: resetsAt)

        if case .limitReached(let seconds) = result {
            // (100 - 80) / rate * 3600 — should be roughly 33 minutes
            XCTAssertGreaterThan(seconds, 0)
            XCTAssertLessThan(seconds, 7200)
        } else {
            XCTFail("Expected limitReached, got \(result)")
        }
    }

    func testProjectionSafe() {
        let now = Date()
        let history = [
            UsageSnapshot(timestamp: now.addingTimeInterval(-3000), sessionUtilization: 10.0, weeklyUtilization: 0),
            UsageSnapshot(timestamp: now, sessionUtilization: 15.0, weeklyUtilization: 0)
        ]
        // Rate: 5% per ~50min ≈ 6%/h. At 15% with 1h to reset → 15 + 6 = 21%
        let resetsAt = now.addingTimeInterval(3600)
        let result = SessionProjection.calculate(history: history, currentUtilization: 15.0, resetsAt: resetsAt)

        if case .safe(let projected) = result {
            XCTAssertGreaterThan(projected, 15)
            XCTAssertLessThan(projected, 100)
        } else {
            XCTFail("Expected safe, got \(result)")
        }
    }

    func testProjectionInsufficientData() {
        let result = SessionProjection.calculate(history: [], currentUtilization: 50.0, resetsAt: Date().addingTimeInterval(3600))
        if case .insufficientData = result {
            // expected
        } else {
            XCTFail("Expected insufficientData")
        }
    }

    func testProjectionNoResetDate() {
        let now = Date()
        let history = [
            UsageSnapshot(timestamp: now.addingTimeInterval(-600), sessionUtilization: 10.0, weeklyUtilization: 0),
            UsageSnapshot(timestamp: now, sessionUtilization: 20.0, weeklyUtilization: 0)
        ]
        let result = SessionProjection.calculate(history: history, currentUtilization: 20.0, resetsAt: nil)
        if case .insufficientData = result {
            // expected
        } else {
            XCTFail("Expected insufficientData")
        }
    }

    func testProjectionZeroOrNegativeRate() {
        let now = Date()
        let history = [
            UsageSnapshot(timestamp: now.addingTimeInterval(-600), sessionUtilization: 50.0, weeklyUtilization: 0),
            UsageSnapshot(timestamp: now, sessionUtilization: 50.0, weeklyUtilization: 0)
        ]
        // Rate = 0 → insufficientData
        let result = SessionProjection.calculate(history: history, currentUtilization: 50.0, resetsAt: now.addingTimeInterval(3600))
        if case .insufficientData = result {
            // expected
        } else {
            XCTFail("Expected insufficientData for zero rate")
        }
    }

    // MARK: - UsageLevel

    func testUsageLevelValues() {
        XCTAssertEqual(UsageLevel.ok.rawValue, "ok")
        XCTAssertEqual(UsageLevel.warning.rawValue, "warning")
        XCTAssertEqual(UsageLevel.critical.rawValue, "critical")
    }

    // MARK: - AuthMethod

    func testAuthMethodRawValues() {
        XCTAssertEqual(AuthMethod.none.rawValue, "none")
        XCTAssertEqual(AuthMethod.claudeCode.rawValue, "Claude Code")
        XCTAssertEqual(AuthMethod.oauth.rawValue, "OAuth (Browser)")
    }
}
