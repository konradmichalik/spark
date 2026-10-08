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

    /// No fresh value: connection lost, sign-in needed, a failed fetch, or no update for an hour
    /// (polling runs every 5 to 30 minutes).
    static func isStale(needsReconnect: Bool, needsSignIn: Bool, hasError: Bool, lastUpdated: Date, now: Date) -> Bool {
        needsReconnect || needsSignIn || hasError || now.timeIntervalSince(lastUpdated) > 3600
    }

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

/// The connection facts of the one provider the menu bar shows. Each provider fills in only its
/// own, so Claude's reconnect state never dims or labels Codex (and the other way round).
struct MenuBarConnection: Equatable {
    let needsReconnect: Bool
    let needsSignIn: Bool
    let hasError: Bool
    let lastUpdated: Date

    /// A logged-out Claude has no fresh value either: it counts as needing a sign-in.
    static func claude(isAuthenticated: Bool, needsReconnect: Bool, hasError: Bool, lastUpdated: Date) -> MenuBarConnection {
        MenuBarConnection(needsReconnect: needsReconnect, needsSignIn: !isAuthenticated, hasError: hasError, lastUpdated: lastUpdated)
    }

    /// `lastUpdated` is nil before the first successful poll, which reads as stale.
    static func codex(needsSignIn: Bool, hasError: Bool, lastUpdated: Date?) -> MenuBarConnection {
        MenuBarConnection(needsReconnect: false, needsSignIn: needsSignIn, hasError: hasError, lastUpdated: lastUpdated ?? .distantPast)
    }

    var isDisconnected: Bool { needsReconnect || needsSignIn }

    func isStale(now: Date) -> Bool {
        MenuBarReading.isStale(
            needsReconnect: needsReconnect, needsSignIn: needsSignIn, hasError: hasError, lastUpdated: lastUpdated, now: now
        )
    }
}
