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

    init(_ projection: ProjectionResult) {
        switch projection {
        case .safe(let value): self.init(projected: min(max(value, 0), 100), reachesLimit: false)
        case .limitReached: self.init(projected: 100, reachesLimit: true)
        case .insufficientData: self.init(projected: nil, reachesLimit: false)
        }
    }
}

struct HistoryColumn: Equatable {
    let session: Double?
    let weekly: Double?
    var time: Date?
}

/// Buckets snapshots of the last `window` into `count` equal slots, oldest first, keeping the
/// latest snapshot per slot. Slots without a snapshot stay empty instead of being stretched.
enum HistoryColumns {
    static func make(_ snapshots: [UsageSnapshot], now: Date, window: TimeInterval = 6 * 3600, count: Int = 34) -> [HistoryColumn] {
        guard count > 0, window > 0 else { return [] }
        let start = now.addingTimeInterval(-window)
        let slot = window / Double(count)
        var latest = [Int: UsageSnapshot]()
        for snapshot in snapshots where snapshot.timestamp >= start && snapshot.timestamp <= now {
            let index = min(Int(snapshot.timestamp.timeIntervalSince(start) / slot), count - 1)
            if let existing = latest[index], existing.timestamp > snapshot.timestamp { continue }
            latest[index] = snapshot
        }
        return (0..<count).map { index in
            guard let snapshot = latest[index] else { return HistoryColumn(session: nil, weekly: nil) }
            return HistoryColumn(session: snapshot.sessionUtilization, weekly: snapshot.weeklyUtilization, time: snapshot.timestamp)
        }
    }
}

/// Short values for the overview rows (docs/design/rules.md, "Navigation").
enum OverviewSummary {
    static func statisticsValue(cost: Double?, messages: Int?) -> String? {
        if let cost {
            let parts = UsageFormat.cost(cost)
            return "≈ $\(parts.number)\(parts.unit.replacingOccurrences(of: "$", with: ""))"
        }
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

/// The forecast tooltip on the session bar: projection and its rate, burn rate, and what the
/// time marker means. One to three lines (docs/design/rules.md, "Tooltips").
enum ForecastDetail {
    static func text(
        projection: ProjectionResult,
        utilization: Double,
        secondsToReset: TimeInterval?,
        tokensPerMinute: Int?
    ) -> String? {
        var lines: [String] = []
        switch projection {
        case .safe(let projected):
            let rate = secondsToReset.flatMap { $0 > 0 ? (projected - utilization) / ($0 / 3600) : nil }
            lines.append("~\(Int(projected.rounded()))% at reset" + rateSuffix(rate))
        case .limitReached(let seconds):
            let rate = seconds > 0 ? (100 - utilization) / (seconds / 3600) : nil
            lines.append("Limit in ~\(seconds.shortDuration)" + rateSuffix(rate))
        case .insufficientData:
            break
        }
        if let tokensPerMinute {
            lines.append("\(formatTokenCount(tokensPerMinute)) tokens per minute, last \(Int(BurnRate.window / 60)) min")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// The one forecast fact that stays on screen: when the limit will be hit before the reset.
    static func limitWarning(_ projection: ProjectionResult) -> String? {
        guard case .limitReached(let seconds) = projection else { return nil }
        return "Limit in ~\(seconds.shortDuration)"
    }

    private static func rateSuffix(_ rate: Double?) -> String {
        guard let rate, rate > 0.5 else { return "" }
        return ", rising ~\(Int(rate.rounded()))%/h"
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

/// The explaining tooltip of a dot bar: what the fill means, then the hollow dots, the marker
/// and the reset, each only when the bar shows it.
enum BarTooltip {
    static func text(window: String, forecast: String?, elapsed: Double?, reset: String?) -> String {
        var lines = ["Share of the \(window) limit used"]
        if let forecast { lines.append("Hollow dots: \(forecast)") }
        if let elapsed { lines.append("Marker: \(Int((elapsed * 100).rounded()))% of the window has passed") }
        if let reset { lines.append("Resets \(reset)") }
        return lines.joined(separator: "\n")
    }
}

/// Clock times under the history card: start, middle and end of the window.
enum HistoryAxis {
    static func labels(now: Date, window: TimeInterval, locale: Locale = .current, timeZone: TimeZone = .current) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return [-window, -window / 2, 0].map { formatter.string(from: now.addingTimeInterval($0)) }
    }
}

/// The hover readout of the history card: which column the pointer is on, and what it says.
enum HistoryHover {
    /// The column under `x`, or the nearest one with a value when that slot is empty.
    static func index(x: CGFloat, width: CGFloat, columns: [HistoryColumn]) -> Int? {
        guard width > 0, !columns.isEmpty else { return nil }
        let pointer = min(max(Int(x / width * CGFloat(columns.count)), 0), columns.count - 1)
        return columns.indices
            .filter { columns[$0].session != nil || columns[$0].weekly != nil }
            .min { abs($0 - pointer) < abs($1 - pointer) }
    }

    static func text(
        _ column: HistoryColumn, locale: Locale = .current, timeZone: TimeZone = .current
    ) -> (title: String, body: String)? {
        guard column.session != nil || column.weekly != nil else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let lines = [
            column.session.map { "Session \(UsageFormat.percent($0, locale: locale))" },
            column.weekly.map { "Week \(UsageFormat.percent($0, locale: locale))" }
        ]
        return (column.time.map(formatter.string) ?? "", lines.compactMap { $0 }.joined(separator: "\n"))
    }
}
