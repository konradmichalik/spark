import XCTest
@testable import Spark

final class CodexUsageTests: XCTestCase {

    private func decode(_ json: String) throws -> CodexUsageResponse {
        try JSONDecoder().decode(CodexUsageResponse.self, from: Data(json.utf8))
    }

    func testPlusPlanMapsFiveHourAndWeeklyWindows() throws {
        let response = try decode("""
        {
          "plan_type": "plus",
          "rate_limit": {
            "allowed": true, "limit_reached": false,
            "primary_window": { "used_percent": 42, "limit_window_seconds": 18000, "reset_after_seconds": 3600, "reset_at": 1791360000 },
            "secondary_window": { "used_percent": 71, "limit_window_seconds": 604800, "reset_after_seconds": 90000, "reset_at": 1791446400 }
          },
          "credits": { "has_credits": false, "unlimited": false, "balance": null }
        }
        """)

        let usage = CodexUsage(response: response)

        XCTAssertEqual(usage.usageData.session?.utilization, 42)
        XCTAssertEqual(usage.usageData.weekly?.utilization, 71)
        XCTAssertEqual(usage.usageData.session?.resetsAtDate, Date(timeIntervalSince1970: 1_791_360_000))
        XCTAssertEqual(usage.usageData.weekly?.resetsAtDate, Date(timeIntervalSince1970: 1_791_446_400))
        XCTAssertEqual(usage.planType, "plus")
        XCTAssertEqual(usage.planDisplayName, "Plus")
        XCTAssertNil(usage.creditsBalance)
        XCTAssertTrue(usage.additionalLimits.isEmpty)
    }

    /// Pro has no 5h window: the weekly window arrives as `primary_window`. Position must not
    /// decide the label, or the weekly quota would be drawn as "Session (5h)".
    func testWeeklyWindowInPrimarySlotMapsToWeekly() throws {
        let response = try decode("""
        {
          "plan_type": "pro",
          "rate_limit": {
            "allowed": true, "limit_reached": false,
            "primary_window": { "used_percent": 12, "limit_window_seconds": 604800, "reset_after_seconds": 90000, "reset_at": 1791446400 },
            "secondary_window": null
          }
        }
        """)

        let usage = CodexUsage(response: response)

        XCTAssertNil(usage.usageData.session)
        XCTAssertEqual(usage.usageData.weekly?.utilization, 12)
        XCTAssertEqual(usage.planDisplayName, "Pro")
    }

    func testUnusualWindowLengthBecomesAdditionalLimit() throws {
        let response = try decode("""
        {
          "plan_type": "team",
          "rate_limit": {
            "allowed": true, "limit_reached": false,
            "primary_window": { "used_percent": 5, "limit_window_seconds": 86400, "reset_after_seconds": 100, "reset_at": 1791360000 }
          }
        }
        """)

        let usage = CodexUsage(response: response)

        XCTAssertNil(usage.usageData.session)
        XCTAssertNil(usage.usageData.weekly)
        XCTAssertEqual(usage.additionalLimits.map(\.label), ["Daily"])
        XCTAssertEqual(usage.additionalLimits.first?.bucket.utilization, 5)
    }

    func testAdditionalRateLimitsAreNamedByLimitName() throws {
        let response = try decode("""
        {
          "plan_type": "pro",
          "rate_limit": null,
          "additional_rate_limits": [
            {
              "limit_name": "GPT-5.5 Codex Max",
              "metered_feature": "codex_max",
              "rate_limit": {
                "allowed": true, "limit_reached": false,
                "primary_window": { "used_percent": 33, "limit_window_seconds": 604800, "reset_after_seconds": 10, "reset_at": 1791446400 }
              }
            },
            { "limit_name": "Empty", "metered_feature": "x", "rate_limit": null }
          ]
        }
        """)

        let usage = CodexUsage(response: response)

        XCTAssertEqual(usage.additionalLimits.count, 1)
        XCTAssertEqual(usage.additionalLimits.first?.label, "GPT-5.5 Codex Max (Weekly)")
        XCTAssertEqual(usage.additionalLimits.first?.bucket.utilization, 33)
    }

    func testCreditsBalanceShownOnlyWhenLimited() throws {
        let limited = try decode("""
        { "plan_type": "business", "credits": { "has_credits": true, "unlimited": false, "balance": "12.50" } }
        """)
        let unlimited = try decode("""
        { "plan_type": "enterprise", "credits": { "has_credits": true, "unlimited": true, "balance": "0" } }
        """)

        XCTAssertEqual(CodexUsage(response: limited).creditsBalance, "12.50")
        XCTAssertNil(CodexUsage(response: unlimited).creditsBalance)
    }

    func testMinimalAndUnknownPayloadDecodes() throws {
        let response = try decode("""
        { "plan_type": "something_new", "spend_control": { "whatever": 1 }, "rate_limit_reached_type": { "type": "rate_limit_reached" } }
        """)

        let usage = CodexUsage(response: response)

        XCTAssertNil(usage.usageData.session)
        XCTAssertNil(usage.usageData.weekly)
        XCTAssertEqual(usage.planDisplayName, "Something New")
        XCTAssertTrue(usage.limitReached)
    }

    func testLimitReachedFlagFromRateLimit() throws {
        let response = try decode("""
        { "plan_type": "plus", "rate_limit": { "allowed": false, "limit_reached": true } }
        """)

        XCTAssertTrue(CodexUsage(response: response).limitReached)
    }
}
