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

/// The words and shares of the Statistics screen.
/// What the "Tokens" figure counts, said the same way wherever it appears: fresh tokens, never
/// the cache reads or cached input that a provider replays on every turn.
enum TokenWording {
    static let claude = "Fresh tokens: input, output and cache writes. Cache reads are not counted: that is context Claude re-reads "
        + "on every turn, so it is far larger and says little about what you used."
    static let codex = "Fresh tokens: input and output. Cached input is not counted: that is context Codex re-sends "
        + "on every turn, so it is far larger and says little about what you used."
    static let volume = "Fresh tokens of the days in this range that have ended: input, output and cache writes. "
        + "Cache reads, the context re-read on every turn, are not counted."

    /// Definition first, then the averages when there are any, then the raw breakdown.
    static func withBreakdown(_ definition: String, _ breakdown: String, average: String? = nil) -> String {
        [definition, average, breakdown].compactMap { $0 }.joined(separator: "\n")
    }
}

/// The averages behind the Messages, Sessions and Tokens tiles, as the sentence their tooltips
/// show. Per day counts only the days on which tokens were used, so idle days do not water the
/// average down; with a single active day it would repeat the totals and is left out.
struct StatisticsAverages: Equatable {
    let messages: String?
    let sessions: String?
    let tokens: String?

    init(activeDays: Int, messages: Int, sessions: Int, tokens: Int, locale: Locale = .current) {
        func number(_ value: Double) -> String {
            value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        }
        func noun(_ count: Double, _ singular: String, _ plural: String) -> String {
            number(count) == "1" ? singular : plural
        }
        let perSession = sessions > 0 ? Double(sessions) : nil
        let perDay = activeDays > 1 ? Double(activeDays) : nil
        self.messages = perSession.flatMap { sessions in
            let average = Double(messages) / sessions
            return messages > 0 ? Self.sentence(number(average), noun(average, "message", "messages"), "session") : nil
        }
        self.sessions = perDay.flatMap { days in
            let average = Double(sessions) / days
            return sessions > 0 ? Self.sentence(number(average), noun(average, "session", "sessions"), "active day") : nil
        }
        var tokenLines: [String] = []
        if let perSession, tokens > 0 {
            tokenLines.append("Average \(formatTokenCount(Int((Double(tokens) / perSession).rounded()))) tokens per session")
        }
        if let perDay, tokens > 0 {
            tokenLines.append("Average \(formatTokenCount(Int((Double(tokens) / perDay).rounded()))) tokens per active day")
        }
        self.tokens = tokenLines.isEmpty ? nil : tokenLines.joined(separator: "\n")
    }

    private static func sentence(_ value: String, _ noun: String, _ unit: String) -> String {
        "Average \(value) \(noun) per \(unit)"
    }
}

enum StatisticsText {
    static func costTooltip(_ cost: CostSummary) -> String {
        let estimate = "Estimated: tokens priced at API list prices. Not what your subscription costs."
        guard !cost.unpricedModels.isEmpty else { return estimate }
        return estimate + " No price for \(cost.unpricedModels.joined(separator: ", "))."
    }

    /// A list entry's share of the largest one, as the percent its dot bar fills.
    static func share(_ value: Int, of largest: Int) -> Double {
        largest > 0 ? Double(value) / Double(largest) * 100 : 0
    }

    static func projectTooltip(tokens: Int, cost: Double?) -> String {
        let lines = ["\(formatTokenCount(tokens)) tokens", cost.map { "\u{2248} \(formatCost($0)) at API list prices" }]
        return lines.compactMap { $0 }.joined(separator: "\n")
    }

    static func rankedModels(_ stats: CodexSessionStats) -> [(name: String, tokens: Int)] {
        stats.modelTokens
            .filter { $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (name: $0.key, tokens: $0.value) }
    }
}
