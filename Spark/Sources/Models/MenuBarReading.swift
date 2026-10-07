import Foundation

enum UsageProvider: String, CaseIterable, SegmentLabeled {
    case claude, codex

    var segmentLabel: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    var segmentIcon: SegmentIcon? {
        switch self {
        case .claude: .claudeLogo
        case .codex: .tabler(.brandOpenai)
        }
    }
}

extension UsageProvider {
    /// The `@AppStorage` key of the popover tab the user opened last. The menu bar shows the
    /// same provider, so switching tabs is how a user picks what the menu bar reports.
    static let selectionKey = "selectedProvider"
}

/// What the menu bar label shows: `value` drives the ring and its tone, `text` is the
/// percentage next to it, `provider` the tab the value belongs to.
struct MenuBarReading: Equatable {
    let value: Double
    let text: String
    let provider: UsageProvider

    /// The selected provider's value. Falls back to Claude when Codex is selected but not
    /// connected, so the label never goes blank after Codex is signed out.
    static func resolve(
        claude: UsageData,
        codex: CodexUsage?,
        value valueMode: String,
        provider: UsageProvider,
        locale: Locale = .current
    ) -> MenuBarReading {
        if provider == .codex, let codex {
            return single(codexValue(codex, mode: valueMode), .codex, locale: locale)
        }
        return single(claudeValue(claude, mode: valueMode), .claude, locale: locale)
    }

    /// One provider's value for a `menuBarValue` mode, or nil when that provider has no data.
    static func providerValue(for provider: UsageProvider, claude: UsageData, codex: CodexUsage?, mode: String) -> Double? {
        switch provider {
        case .claude: claudeValue(claude, mode: mode)
        case .codex: codex.map { codexValue($0, mode: mode) }
        }
    }

    func level(warning: Double, critical: Double) -> UsageLevel {
        if value >= critical { return .critical }
        if value >= warning { return .warning }
        return .ok
    }

    private static func single(_ value: Double, _ provider: UsageProvider, locale: Locale) -> MenuBarReading {
        MenuBarReading(value: value, text: UsageFormat.percent(value, locale: locale), provider: provider)
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
