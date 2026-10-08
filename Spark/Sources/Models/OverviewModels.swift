import Foundation

/// What the session bar draws for the projection: hollow dots up to `projected`, red when the
/// limit is reached before the reset (docs/design/rules.md, "Dot language").
struct SessionForecast: Equatable {
    let projected: Double?
    let reachesLimit: Bool

    init(projected: Double?, reachesLimit: Bool) {
        self.projected = projected
        self.reachesLimit = reachesLimit
    }

    /// The forecast's own colour, for hollow dots, marker and forecast line: grey while the
    /// session lands below 90 %, ochre from 90 %, red when it reaches the limit before the reset.
    var tone: UsageTone {
        if reachesLimit { return .critical }
        guard let projected else { return .normal }
        return projected >= 90 ? .warning : .normal
    }

    init(_ projection: ProjectionResult) {
        switch projection {
        case .safe(let value): self.init(projected: min(max(value, 0), 100), reachesLimit: false)
        case .limitReached: self.init(projected: 100, reachesLimit: true)
        case .insufficientData: self.init(projected: nil, reachesLimit: false)
        }
    }
}

/// Short values for the overview rows (docs/design/rules.md, "Navigation").
enum OverviewSummary {
    static func statisticsValue(tokens: Int?, cost: Double?, messages: Int?) -> String? {
        let tokenText = tokens.flatMap { $0 > 0 ? "\(formatTokenCount($0)) tok" : nil }
        let costText = cost.map { cost -> String in
            let parts = UsageFormat.cost(cost)
            return "\u{2248} $\(parts.number)\(parts.unit.replacingOccurrences(of: "$", with: ""))"
        }
        let parts = [tokenText, costText].compactMap { $0 }
        if !parts.isEmpty { return parts.joined(separator: " \u{00B7} ") }
        guard let messages else { return nil }
        return messages == 1 ? "1 message" : "\(messages) messages"
    }

    static func limitsValue(extraLimits: Int, plan: String?) -> String? {
        if extraLimits > 0 { return "\(extraLimits) more" }
        return plan
    }
}

/// The popover's two navigation levels: the overview and one detail screen at a time.
enum PopoverScreen: Hashable {
    case overview, history, sessions, statistics, limits

    var title: String {
        switch self {
        case .overview: ""
        case .history: "History"
        case .sessions: "Active sessions"
        case .statistics: "Statistics"
        case .limits: "All limits"
        }
    }
}

/// The tooltip of a provider tab: plan and sign-in path, whichever is known.
enum ProviderTabSummary {
    static func tooltip(plan: String?, signIn: String?) -> String? {
        let parts = [plan, signIn].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// What the overview leads with when a provider reports no session window: Codex Pro sends only
/// the weekly window, Free a single 30-day one that lands among the other limits.
enum HeadlineLimit {
    struct Headline {
        let label: String
        let bucket: UsageBucket
        let window: TimeInterval
    }

    static func withoutSession(weekly: UsageBucket?, others: [CodexNamedLimit]) -> Headline? {
        if let weekly { return Headline(label: "WEEK", bucket: weekly, window: 7 * 86_400) }
        return others.first.map { Headline(label: $0.label.uppercased(), bucket: $0.bucket, window: TimeInterval($0.windowSeconds)) }
    }

    static func emptyText(limitReached: Bool) -> String {
        limitReached ? "Usage limit reached" : "No limits reported for this plan"
    }

    /// Tooltips only show on hover, so VoiceOver gets the forecast through the value.
    static func accessibilityValue(_ value: Double, detail: String?, locale: Locale = .current) -> String {
        [UsageFormat.percent(value, locale: locale), detail].compactMap { $0 }.joined(separator: ". ")
    }
}
