@testable import Spark
import XCTest

final class AllLimitsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let english = Locale(identifier: "en_US")

    private func bucket(_ value: Double, resetIn: TimeInterval? = nil) -> UsageBucket {
        UsageBucket(utilization: value, resetsAt: resetIn.map { ISO8601DateFormatter().string(from: now.addingTimeInterval($0)) })
    }

    private func claude(_ data: UsageData, models: [ModelFamily] = [], local: [ModelFamily: Int] = [:]) -> LimitSections {
        AllLimits.claude(data, models: models, localTokens: local, warning: 75, critical: 90, now: now, locale: english)
    }

    func testClaudeListsSessionWeekAndTheShownModels() {
        let data = UsageData(session: bucket(45), weekly: bucket(48), weeklySonnet: bucket(92), weeklyOpus: bucket(78))
        let sections = claude(data, models: [.opus, .sonnet])
        XCTAssertEqual(sections.limits.map(\.label), ["Session · 5h", "Week · all models", "Week · Opus", "Week · Sonnet"])
        XCTAssertEqual(sections.limits.map(\.tone), [.normal, .normal, .warning, .critical])
        XCTAssertTrue(sections.extras.isEmpty)
    }

    func testTooltipNamesTheResetAndWhatIsLeft() {
        let sections = claude(UsageData(session: bucket(78, resetIn: 3600)))
        let tooltip = sections.limits.first?.tooltip ?? ""
        XCTAssertTrue(tooltip.hasPrefix("Resets "), tooltip)
        XCTAssertTrue(tooltip.hasSuffix("\n22% left"), tooltip)
        XCTAssertEqual(claude(UsageData(session: bucket(100))).limits.first?.tooltip, "0% left")
    }

    func testMarkerShowsHowMuchOfTheWindowHasPassed() {
        let sections = claude(UsageData(weekly: bucket(30, resetIn: 3.5 * 86_400)))
        XCTAssertEqual(sections.limits.first?.elapsed ?? 0, 0.5, accuracy: 0.001)
    }

    func testModelWithoutItsOwnLimitShowsLocalTokens() {
        let sections = claude(UsageData(weekly: bucket(48)), models: [.opus, .fable], local: [.opus: 1_200_000])
        let opus = sections.limits.last
        XCTAssertEqual(sections.limits.map(\.label), ["Week · all models", "Week · Opus"])
        XCTAssertNil(opus?.value)
        XCTAssertEqual(opus?.detail, "1.2M local")
    }

    func testExtraUsageIsAnExtraLine() {
        let extra = ExtraUsage(
            isEnabled: true, monthlyLimit: 5000, usedCredits: 420, utilization: nil, currency: "USD", decimalPlaces: 2, disabledReason: nil
        )
        let line = claude(UsageData(session: bucket(10), extraUsage: extra)).extras.first
        XCTAssertEqual(line?.label, "Extra usage")
        XCTAssertEqual(line?.value ?? 0, 8.4, accuracy: 0.001)
        XCTAssertNotNil(line?.detail)
    }

    func testCodexKeepsItsWindowsAndCredits() throws {
        let json = """
        {"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":41,"limit_window_seconds":18000},
        "secondary_window":{"used_percent":18,"limit_window_seconds":604800}},
        "additional_rate_limits":[{"limit_name":"GPT-5-Codex","rate_limit":{"primary_window":{"used_percent":95,"limit_window_seconds":2592000}}}],
        "credits":{"has_credits":true,"unlimited":false,"balance":"12.50"}}
        """
        let response = try JSONDecoder().decode(CodexUsageResponse.self, from: Data(json.utf8))
        let sections = AllLimits.codex(CodexUsage(response: response, now: now), warning: 75, critical: 90, now: now, locale: english)
        XCTAssertEqual(sections.limits.map(\.label), ["Session · 5h", "Week", "GPT-5-Codex (30 days)"])
        XCTAssertEqual(sections.limits.last?.tone, .critical)
        XCTAssertEqual(sections.extras.map(\.label), ["Credits"])
        XCTAssertEqual(sections.extras.first?.detail, "12.50")
    }
}
