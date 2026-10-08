import XCTest
@testable import Spark

final class ModelsTests: XCTestCase {

    // MARK: - UsageAPIResponse Decoding

    func testDecodeUsageAPIResponse() throws {
        let json = Data("""
        {
            "five_hour": { "utilization": 42.5, "resets_at": "2026-03-30T18:00:00Z" },
            "seven_day": { "utilization": 65.0, "resets_at": "2026-04-05T00:00:00Z" },
            "seven_day_sonnet": { "utilization": 30.0, "resets_at": "2026-04-05T00:00:00Z" },
            "seven_day_opus": { "utilization": 12.0, "resets_at": "2026-04-05T00:00:00Z" },
            "seven_day_fable": { "utilization": 8.0, "resets_at": "2026-04-05T00:00:00Z" }
        }
        """.utf8)

        let response = try JSONDecoder().decode(UsageAPIResponse.self, from: json)
        XCTAssertEqual(response.fiveHour?.utilization, 42.5)
        XCTAssertEqual(response.sevenDay?.utilization, 65.0)
        XCTAssertEqual(response.sevenDaySonnet?.utilization, 30.0)
        XCTAssertEqual(response.sevenDayOpus?.utilization, 12.0)
        XCTAssertEqual(response.sevenDayFable?.utilization, 8.0)
        XCTAssertNotNil(response.fiveHour?.resetsAt)
    }

    /// The live API may not report a Fable-specific bucket at all yet — decoding must tolerate
    /// its absence exactly like it already does for a missing Opus bucket.
    func testDecodeUsageAPIResponseWithoutFableBucket() throws {
        let json = Data("""
        {
            "five_hour": { "utilization": 10.0 }
        }
        """.utf8)

        let response = try JSONDecoder().decode(UsageAPIResponse.self, from: json)
        XCTAssertNil(response.sevenDayFable)
    }

    /// The live API includes many extra null buckets (codenames) and an extra_usage
    /// object — decoding must tolerate unknown keys and a null opus bucket.
    func testDecodeUsageAPIResponseFullPayload() throws {
        let json = Data("""
        {
            "five_hour": { "utilization": 11, "resets_at": "2026-06-12T11:20:00.999581+00:00" },
            "seven_day": { "utilization": 16, "resets_at": "2026-06-14T04:00:00.999602+00:00" },
            "seven_day_oauth_apps": null,
            "seven_day_opus": null,
            "seven_day_sonnet": { "utilization": 0, "resets_at": null },
            "seven_day_cowork": null,
            "tangelo": null,
            "extra_usage": {
                "is_enabled": true, "monthly_limit": null, "used_credits": 2.4,
                "utilization": null, "currency": "EUR", "disabled_reason": null
            }
        }
        """.utf8)

        let response = try JSONDecoder().decode(UsageAPIResponse.self, from: json)
        XCTAssertEqual(response.fiveHour?.utilization, 11)
        XCTAssertNil(response.sevenDayOpus)
        XCTAssertEqual(response.sevenDaySonnet?.utilization, 0)
        XCTAssertEqual(response.extraUsage?.isEnabled, true)
        XCTAssertEqual(response.extraUsage?.usedCredits, 2.4)
        XCTAssertEqual(response.extraUsage?.currency, "EUR")
        XCTAssertTrue(response.extraUsage?.hasSpend ?? false)
        XCTAssertNotNil(response.extraUsage?.formattedSpend)
    }

    func testDecodeUsageAPIResponsePartial() throws {
        let json = Data("""
        {
            "five_hour": { "utilization": 10.0 }
        }
        """.utf8)

        let response = try JSONDecoder().decode(UsageAPIResponse.self, from: json)
        XCTAssertEqual(response.fiveHour?.utilization, 10.0)
        XCTAssertNil(response.fiveHour?.resetsAt)
        XCTAssertNil(response.sevenDay)
        XCTAssertNil(response.sevenDaySonnet)
    }

    // MARK: - UsageBucket

    func testResetsAtDateParsing() throws {
        let json = Data("""
        { "utilization": 50.0, "resets_at": "2026-03-30T18:30:00Z" }
        """.utf8)

        let bucket = try JSONDecoder().decode(UsageBucket.self, from: json)
        XCTAssertNotNil(bucket.resetsAtDate)
    }

    func testResetsAtDateWithFractionalSeconds() throws {
        let json = Data("""
        { "utilization": 50.0, "resets_at": "2026-03-30T18:30:00.123Z" }
        """.utf8)

        let bucket = try JSONDecoder().decode(UsageBucket.self, from: json)
        XCTAssertNotNil(bucket.resetsAtDate)
    }

    func testResetsAtDateNil() throws {
        let json = Data("""
        { "utilization": 50.0 }
        """.utf8)

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
        let json = Data("""
        { "utilization": 80.0 }
        """.utf8)
        let session = try JSONDecoder().decode(UsageBucket.self, from: json)

        let json2 = Data("""
        { "utilization": 40.0 }
        """.utf8)
        let weekly = try JSONDecoder().decode(UsageBucket.self, from: json2)

        let data = UsageData(session: session, weekly: weekly)
        XCTAssertEqual(data.sessionUtilization, 80.0)
        XCTAssertEqual(data.weeklyUtilization, 40.0)
        XCTAssertEqual(data.maxUtilization, 80.0)
    }

    // MARK: - ClaudeServiceStatus

    func testStatusDecoding() throws {
        let json = Data("\"operational\"".utf8)
        let status = try JSONDecoder().decode(ClaudeServiceStatus.self, from: json)
        XCTAssertEqual(status, .operational)
        XCTAssertTrue(status.isHealthy)
    }

    func testStatusNoneIsHealthy() throws {
        let json = Data("\"none\"".utf8)
        let status = try JSONDecoder().decode(ClaudeServiceStatus.self, from: json)
        XCTAssertEqual(status, .none)
        XCTAssertTrue(status.isHealthy)
    }

    func testStatusMajorOutage() throws {
        let json = Data("\"major_outage\"".utf8)
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
        let json = Data("""
        {
            "status": { "indicator": "none", "description": "All Systems Operational" },
            "components": [
                { "name": "API", "status": "operational" },
                { "name": "Claude.ai", "status": "operational" }
            ]
        }
        """.utf8)

        let response = try JSONDecoder().decode(StatusPageResponse.self, from: json)
        XCTAssertEqual(response.status.indicator, "none")
        XCTAssertEqual(response.status.description, "All Systems Operational")
        XCTAssertEqual(response.components?.count, 2)
    }

    // MARK: - UsageSnapshot

    func testUsageSnapshotCodable() throws {
        let snapshot = UsageSnapshot(
            sessionUtilization: 42.0,
            weeklyUtilization: 65.0,
            sonnetUtilization: 10.0,
            opusUtilization: 20.0,
            fableUtilization: 5.0,
            extraUsageSpend: 1.5
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)

        XCTAssertEqual(decoded.sessionUtilization, 42.0)
        XCTAssertEqual(decoded.weeklyUtilization, 65.0)
        XCTAssertEqual(decoded.sonnetUtilization, 10.0)
        XCTAssertEqual(decoded.opusUtilization, 20.0)
        XCTAssertEqual(decoded.fableUtilization, 5.0)
        XCTAssertEqual(decoded.extraUsageSpend, 1.5)
        XCTAssertEqual(decoded.id, snapshot.id)
    }

    func testUsageSnapshotDecodesLegacyJSONMissingNewerFields() throws {
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","timestamp":\(Date().timeIntervalSinceReferenceDate),\
        "sessionUtilization":42.0,"weeklyUtilization":65.0}
        """
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(decoded.sessionUtilization, 42.0)
        XCTAssertNil(decoded.sonnetUtilization)
        XCTAssertNil(decoded.opusUtilization)
        XCTAssertNil(decoded.fableUtilization)
        XCTAssertNil(decoded.extraUsageSpend)
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

    // MARK: - ClaudeCodeInstallMethod

    func testInstallMethodMapsNpmGlobal() {
        XCTAssertEqual(ClaudeCodeInstallMethod(rawConfigValue: "npm-global"), .npmGlobal)
    }

    func testInstallMethodMapsHomebrew() {
        XCTAssertEqual(ClaudeCodeInstallMethod(rawConfigValue: "homebrew"), .homebrew)
    }

    func testInstallMethodCollapsesOthersToOther() {
        XCTAssertEqual(ClaudeCodeInstallMethod(rawConfigValue: "native"), .other)
        XCTAssertEqual(ClaudeCodeInstallMethod(rawConfigValue: "local"), .other)
        XCTAssertEqual(ClaudeCodeInstallMethod(rawConfigValue: "standalone"), .other)
        XCTAssertEqual(ClaudeCodeInstallMethod(rawConfigValue: "unknown"), .other)
        XCTAssertEqual(ClaudeCodeInstallMethod(rawConfigValue: "something-future-value"), .other)
        XCTAssertEqual(ClaudeCodeInstallMethod(rawConfigValue: nil), .other)
    }

    func testInstallMethodDisplayLabels() {
        XCTAssertEqual(ClaudeCodeInstallMethod.npmGlobal.displayLabel, "npm")
        XCTAssertEqual(ClaudeCodeInstallMethod.homebrew.displayLabel, "Homebrew")
        XCTAssertEqual(ClaudeCodeInstallMethod.other.displayLabel, "native")
    }

    func testInstallMethodUpdateCommands() {
        XCTAssertEqual(ClaudeCodeInstallMethod.npmGlobal.updateCommand, "npm update -g @anthropic-ai/claude-code")
        XCTAssertEqual(ClaudeCodeInstallMethod.homebrew.updateCommand, "brew upgrade --cask claude-code")
        XCTAssertEqual(ClaudeCodeInstallMethod.other.updateCommand, "claude update")
    }
}
