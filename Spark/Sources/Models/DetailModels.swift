import Foundation

/// A long list shows its first entries and a "Show N more" row that expands in place
/// (docs/design/rules.md, "Navigation").
struct ShowMore: Equatable {
    let total: Int
    let limit: Int

    /// A single hidden entry is shown right away: the row revealing it would take its space.
    var isNeeded: Bool { total > limit + 1 }

    func visibleCount(expanded: Bool) -> Int {
        expanded || !isNeeded ? total : limit
    }

    func label(expanded: Bool) -> String? {
        guard isNeeded else { return nil }
        return expanded ? "Show less" : "Show \(total - limit) more"
    }
}

/// The words of one row on the Active Sessions screen. The session ID and model are secondary,
/// so they live in the row's tooltip (docs/design/rules.md, "Tooltips").
enum ActiveSessionText {
    static func subtitle(_ session: ActiveSession, now: Date = Date()) -> String {
        let elapsed = max(0, now.timeIntervalSince(session.lastActivity))
        return elapsed < 60 ? "just now" : "\(Int(elapsed / 60)) min ago"
    }

    static func tooltip(
        _ session: ActiveSession, locale: Locale = .current, timeZone: TimeZone = .current
    ) -> (title: String, body: String) {
        let format = HistoryAxis.formatter(locale: locale, timeZone: timeZone)
        let lines = [
            session.startedAt.map { "Started \(format.string(from: $0))" },
            "Model: \(session.model ?? "not known yet")"
        ]
        let body = session.model == nil && session.startedAt == nil ? "Model not known yet" : lines.compactMap { $0 }.joined(separator: "\n")
        return ("Session \(session.sessionId.prefix(8).uppercased())", body)
    }

    static func accessibilityLabel(_ session: ActiveSession, now: Date = Date()) -> String {
        let context = session.contextTokens.map { "context \(formatTokenCount($0)) tokens" }
        return [session.displayName, subtitle(session, now: now), context].compactMap { $0 }.joined(separator: ", ")
    }
}
