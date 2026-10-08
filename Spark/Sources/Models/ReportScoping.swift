import Foundation

/// The provider filter of the usage report.
enum ReportScope: String, CaseIterable, SegmentLabeled {
    case all = "All"
    case claude = "Claude"
    case codex = "Codex"

    var segmentLabel: String { rawValue }
}

/// What the report knows about Codex for the shown period and the one before it.
struct CodexReportData: Equatable, Sendable {
    /// Fresh tokens per day key, from the start of the previous period.
    var dayTokens: [String: Int]
    /// Fresh tokens per raw model name, for the shown period.
    var modelTokens: [String: Int]

    var hasUse: Bool { dayTokens.values.contains { $0 > 0 } }

    func tokens(from start: Date, to end: Date, calendar: Calendar) -> Int {
        let first = TranscriptCache.dayKey(for: start, calendar: calendar)
        let last = TranscriptCache.dayKey(for: end, calendar: calendar)
        return dayTokens.filter { $0.key >= first && $0.key <= last }.values.reduce(0, +)
    }
}

struct ScopedTotals: Equatable {
    let current: Int
    let previous: Int
    let trendPercent: Double?
}

/// Which sections the report shows for a scope and how the scopes combine their numbers. The pace
/// graph, API cost, top lists and cache notes only exist for Claude, so Codex alone hides them.
enum ReportScoping {
    /// Without a second provider the filter is gone and the report is Claude's.
    static func effective(_ selected: ReportScope, codexShown: Bool) -> ReportScope {
        codexShown ? selected : .claude
    }

    /// Cached Codex numbers only count while they were scanned for the period now shown, so a
    /// period or provider change never displays the previous scan's totals.
    static func codexData(_ data: CodexReportData?, loadedFor loadedKey: String?, wanted wantedKey: String) -> CodexReportData? {
        loadedKey == wantedKey ? data : nil
    }

    static func showsClaudeSections(_ scope: ReportScope) -> Bool { scope != .codex }

    /// Names a Claude-only section when it sits in a report that also holds Codex numbers.
    static func title(_ base: String, scope: ReportScope) -> String {
        scope == .all ? "\(base) \u{00B7} CLAUDE" : base
    }

    static func costTooltip(_ text: String, scope: ReportScope) -> String {
        scope == .all ? "Claude only. Codex has no price list. \(text)" : text
    }

    static func dayTokens(_ scope: ReportScope, claude: [String: Int], codex: [String: Int]) -> [String: Int] {
        switch scope {
        case .claude: claude
        case .codex: codex
        case .all: claude.merging(codex, uniquingKeysWith: +)
        }
    }

    static func totals(_ scope: ReportScope, report: PeriodReport, codex: CodexReportData?, calendar: Calendar = .current) -> ScopedTotals {
        let claudeShare = scope == .codex ? (0, 0) : (report.currentPeriodTokens, report.previousPeriodTokens)
        let codexShare = scope == .claude ? (0, 0) : (
            codex?.tokens(from: report.rangeStart, to: report.rangeEnd, calendar: calendar) ?? 0,
            codex?.tokens(from: report.previousStart, to: report.previousEnd, calendar: calendar) ?? 0
        )
        let current = claudeShare.0 + codexShare.0
        let previous = claudeShare.1 + codexShare.1
        let trend = previous > 0 ? Double(current - previous) / Double(previous) * 100 : nil
        return ScopedTotals(current: current, previous: previous, trendPercent: trend)
    }

    static func modelRows(_ scope: ReportScope, claude: [ModelRow], codex: CodexReportData?) -> [ModelRow] {
        let claudeRows = scope == .codex ? [] : claude
        let codexRows = scope == .claude ? [] : (codex?.modelTokens ?? [:]).filter { $0.value > 0 }.map { model, tokens in
            ModelRow(
                id: "codex-\(model)", label: model, tokens: tokens, family: .other, cost: nil,
                versions: [ModelRow.Version(label: model, tokens: tokens, cost: nil)]
            )
        }
        return (claudeRows + codexRows).enumerated()
            .sorted { $0.element.tokens != $1.element.tokens ? $0.element.tokens > $1.element.tokens : $0.offset < $1.offset }
            .map(\.element)
    }
}
