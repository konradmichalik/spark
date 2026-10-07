import Foundation

enum UsageProvider: String, CaseIterable, SegmentLabeled {
    case claude, codex

    var segmentLabel: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }
}

/// Which provider the menu bar label reports once Codex is connected. Stored as its raw value in
/// `@AppStorage("menuBarProvider")`, so the raw values are persistence keys and must not change.
enum MenuBarProviderMode: String, CaseIterable {
    case highest, claude, codex, both

    var displayName: String {
        switch self {
        case .highest: "Highest"
        case .claude: "Claude"
        case .codex: "Codex"
        case .both: "Both"
        }
    }
}

/// What the menu bar label shows: `value` drives the ring or bar and its color, `text` is the
/// percentage next to it. `provider` is nil when both providers are shown at once.
struct MenuBarReading: Equatable {
    let value: Double
    let text: String
    let provider: UsageProvider?

    static func resolve(
        claude: UsageData,
        codex: CodexUsage?,
        value valueMode: String,
        mode: MenuBarProviderMode
    ) -> MenuBarReading {
        let claudeValue = Self.claudeValue(claude, mode: valueMode)
        guard let codex else { return single(claudeValue, .claude) }
        let codexValue = Self.codexValue(codex, mode: valueMode)

        switch mode {
        case .claude:
            return single(claudeValue, .claude)
        case .codex:
            return single(codexValue, .codex)
        case .highest:
            return codexValue > claudeValue ? single(codexValue, .codex) : single(claudeValue, .claude)
        case .both:
            return MenuBarReading(
                value: max(claudeValue, codexValue),
                text: "\(Int(claudeValue))% | \(Int(codexValue))%",
                provider: nil
            )
        }
    }

    func level(warning: Double, critical: Double) -> UsageLevel {
        if value >= critical { return .critical }
        if value >= warning { return .warning }
        return .ok
    }

    private static func single(_ value: Double, _ provider: UsageProvider) -> MenuBarReading {
        MenuBarReading(value: value, text: "\(Int(value))%", provider: provider)
    }

    private static func claudeValue(_ data: UsageData, mode: String) -> Double {
        switch mode {
        case "session": data.sessionUtilization
        case "weekly": data.weeklyUtilization
        default: data.maxUtilization
        }
    }

    /// Falls back to the highest window when the plan has no such window, so a Pro plan (no 5h
    /// window) or the Free plan (one 30-day window) never reads as an idle 0%.
    private static func codexValue(_ usage: CodexUsage, mode: String) -> Double {
        switch mode {
        case "session": usage.usageData.session?.utilization ?? usage.maxUtilization
        case "weekly": usage.usageData.weekly?.utilization ?? usage.maxUtilization
        default: usage.maxUtilization
        }
    }
}
