import XCTest
@testable import Spark

final class MenuBarReadingTests: XCTestCase {

    private let claude = UsageData(
        session: UsageBucket(utilization: 42, resetsAt: nil),
        weekly: UsageBucket(utilization: 20, resetsAt: nil)
    )

    private func codex(session: Double?, weekly: Double?, extra: Double? = nil) throws -> CodexUsage {
        func window(_ percent: Double?, seconds: Int) -> String {
            guard let percent else { return "null" }
            return #"{ "used_percent": \#(percent), "limit_window_seconds": \#(seconds) }"#
        }
        let extraJSON = extra.map {
            #"[{ "limit_name": "Max", "rate_limit": { "primary_window": \#(window($0, seconds: 18000)) } }]"#
        } ?? "null"
        let json = """
        {
          "plan_type": "plus",
          "rate_limit": { "primary_window": \(window(session, seconds: 18000)), "secondary_window": \(window(weekly, seconds: 604800)) },
          "additional_rate_limits": \(extraJSON)
        }
        """
        return CodexUsage(response: try JSONDecoder().decode(CodexUsageResponse.self, from: Data(json.utf8)))
    }

    private let enUS = Locale(identifier: "en_US")

    func testWithoutCodexAlwaysShowsClaude() {
        for provider in UsageProvider.allCases {
            let reading = MenuBarReading.resolve(claude: claude, codex: nil, value: "max", provider: provider, locale: enUS)
            XCTAssertEqual(reading.value, 42)
            XCTAssertEqual(reading.text, "42%")
            XCTAssertEqual(reading.provider, .claude)
        }
    }

    func testFollowsTheSelectedProvider() throws {
        let codex = try codex(session: 5, weekly: 60)

        XCTAssertEqual(MenuBarReading.resolve(claude: claude, codex: codex, value: "max", provider: .claude, locale: enUS).value, 42)
        XCTAssertEqual(MenuBarReading.resolve(claude: claude, codex: codex, value: "max", provider: .codex, locale: enUS).value, 60)
        XCTAssertEqual(MenuBarReading.resolve(claude: claude, codex: codex, value: "session", provider: .codex, locale: enUS).value, 5)
        XCTAssertEqual(MenuBarReading.resolve(claude: claude, codex: codex, value: "weekly", provider: .claude, locale: enUS).value, 20)
        XCTAssertEqual(MenuBarReading.resolve(claude: claude, codex: codex, value: "max", provider: .codex, locale: enUS).provider, .codex)
    }

    func testTextFollowsTheLocale() {
        let german = MenuBarReading.resolve(claude: claude, codex: nil, value: "max", provider: .claude, locale: Locale(identifier: "de_DE"))
            .text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
        XCTAssertEqual(german, "42 %")
    }

    /// A plan without the requested window (Pro has no 5h window, Free only a 30-day one) must
    /// not read as 0%: it falls back to the provider's highest window.
    func testMissingCodexWindowFallsBackToHighest() throws {
        let codex = try codex(session: nil, weekly: 30, extra: 80)

        XCTAssertEqual(MenuBarReading.resolve(claude: claude, codex: codex, value: "session", provider: .codex, locale: enUS).value, 80)
        XCTAssertEqual(MenuBarReading.resolve(claude: claude, codex: codex, value: "max", provider: .codex, locale: enUS).value, 80)
    }

    /// The provider tabs show each provider's session value, with the same fallback as the
    /// menu bar when a Codex plan has no session window.
    func testSessionValuePerProvider() throws {
        let withSession = try codex(session: 12, weekly: 70)
        let withoutSession = try codex(session: nil, weekly: 30, extra: 80)

        XCTAssertEqual(MenuBarReading.providerValue(for: .claude, claude: claude, codex: withSession, mode: "session"), 42)
        XCTAssertEqual(MenuBarReading.providerValue(for: .codex, claude: claude, codex: withSession, mode: "session"), 12)
        XCTAssertEqual(MenuBarReading.providerValue(for: .codex, claude: claude, codex: withoutSession, mode: "session"), 80)
        XCTAssertNil(MenuBarReading.providerValue(for: .codex, claude: claude, codex: nil, mode: "session"))
    }

    func testLevelFollowsValue() {
        let reading = MenuBarReading(value: 80, text: "80%", provider: .codex)

        XCTAssertEqual(reading.level(warning: 75, critical: 90), .warning)
        XCTAssertEqual(reading.level(warning: 50, critical: 80), .critical)
        XCTAssertEqual(reading.level(warning: 85, critical: 95), .ok)
    }
}
