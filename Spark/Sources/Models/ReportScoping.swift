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
    /// Fresh tokens per Codex working directory, for the shown period.
    var projectTokens: [String: Int] = [:]
    /// Sessions with activity in the shown period.
    var sessionCount = 0
    /// The shown period's sessions with the most fresh tokens.
    var topSessions: [SessionUsage] = []

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

/// Which sections the report shows for a scope and how the scopes combine their numbers. Pace,
/// API cost and cache notes only use Claude data.
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

    /// The providers a scope shows, Claude first.
    static func providers(_ scope: ReportScope) -> [ReportProvider] {
        switch scope {
        case .claude: [.claude]
        case .codex: [.codex]
        case .all: [.claude, .codex]
        }
    }

    /// API cost keeps its slot in every scope; outside Claude's own scope this says why the value
    /// is partial or missing.
    static func costNote(_ scope: ReportScope) -> String? {
        switch scope {
        case .claude: nil
        case .all: "Claude only"
        case .codex: "Not calculated for Codex"
        }
    }

    static func costTooltip(_ text: String, scope: ReportScope) -> String {
        scope == .all ? "Claude only. \(text)" : text
    }

    static func dayTokens(_ scope: ReportScope, claude: [String: Int], codex: [String: Int]) -> [String: Int] {
        switch scope {
        case .claude: claude
        case .codex: codex
        case .all: claude.merging(codex, uniquingKeysWith: +)
        }
    }

    /// Project lists stay provider-specific in All, matching the report's existing Claude-only list.
    static func projectTokens(_ scope: ReportScope, claude: [String: Int], codex: CodexReportData?) -> [String: Int] {
        scope == .codex ? codex?.projectTokens ?? [:] : claude
    }

    /// Claude's fresh tokens per day from the rollups and the live scan. Rollups outlive deleted
    /// transcripts, so a total summed from them needs their days too, or its average runs high.
    static func persistedDayTokens(rollups: [String: DailyRollup], live: [String: Int]) -> [String: Int] {
        rollups.mapValues(\.real).merging(live, uniquingKeysWith: max)
    }

    /// The days of the range on which the scope used tokens.
    static func activeDays(_ dayTokens: [String: Int], from start: Date, to end: Date, calendar: Calendar = .current) -> Int {
        let first = TranscriptCache.dayKey(for: start, calendar: calendar)
        let last = TranscriptCache.dayKey(for: end, calendar: calendar)
        return dayTokens.filter { $0.key >= first && $0.key <= last && $0.value > 0 }.count
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

    /// Sessions with activity in the period, both providers added up in All.
    static func sessionCount(_ scope: ReportScope, report: PeriodReport, codex: CodexReportData?) -> Int {
        (scope == .codex ? 0 : report.sessionCount) + (scope == .claude ? 0 : codex?.sessionCount ?? 0)
    }

    /// The tokens of All split into Claude and Codex, Claude first, each with its share in percent.
    static func providerSplit(report: PeriodReport, codex: CodexReportData?, calendar: Calendar = .current) -> [ReportProviderShare] {
        let tokens = ReportProvider.allCases.map { provider in
            (provider, totals(provider == .claude ? .claude : .codex, report: report, codex: codex, calendar: calendar).current)
        }
        let total = tokens.reduce(0) { $0 + $1.1 }
        return tokens.map { ReportProviderShare(provider: $0.0, tokens: $0.1, percent: StatisticsText.share($0.1, of: total)) }
    }

    static func modelRows(_ scope: ReportScope, claude: [ModelRow], codex: CodexReportData?) -> [ModelRow] {
        let claudeRows = scope == .codex ? [] : claude
        let codexRows = scope == .claude ? [] : (codex?.modelTokens ?? [:]).filter { $0.value > 0 }.map { model, tokens in
            ModelRow(
                id: "codex-\(model)", label: model, tokens: tokens, family: .other, cost: nil,
                versions: [ModelRow.Version(label: model, tokens: tokens, cost: nil)], providers: [.codex]
            )
        }
        return (claudeRows + codexRows).enumerated()
            .sorted { $0.element.tokens != $1.element.tokens ? $0.element.tokens > $1.element.tokens : $0.offset < $1.offset }
            .map(\.element)
    }

    /// The scope's projects, largest first. In All a working directory both providers used is one
    /// row: Claude's `cwd` and Codex's keys are both the directory the CLI ran in. A Claude
    /// project whose transcripts never named a `cwd` cannot be matched and stays its own row.
    static func projectRows(_ scope: ReportScope, claude: [ProjectUsage], codex: CodexReportData?) -> [ReportProjectRow] {
        let claudeRows: [ReportProjectRow] = scope == .codex ? [] : claude.map { project in
            let path = project.cwd.map(normalizedPath)
            return ReportProjectRow(
                id: path ?? project.key, name: project.displayName, path: path, tokens: project.tokens,
                providers: [.claude], claudeKeys: [project.key]
            )
        }
        let codexRows: [ReportProjectRow] = scope == .claude ? [] : (codex?.projectTokens ?? [:]).filter { $0.value > 0 }.map { key, tokens in
            let path = normalizedPath(key)
            return ReportProjectRow(
                id: path, name: ProjectFamily.displayName(forKey: path, cwd: path), path: path, tokens: tokens,
                providers: [.codex], claudeKeys: []
            )
        }
        let byDirectory = Dictionary(grouping: claudeRows + codexRows, by: \.id)
        let merged: [ReportProjectRow] = byDirectory.values.compactMap { rows in
            rows.dropFirst().reduce(rows.first) { merged, row in merged?.merging(row) }
        }
        return merged.sorted { $0.tokens != $1.tokens ? $0.tokens > $1.tokens : $0.id < $1.id }
    }

    /// The CLIs write the directory as the shell had it; only a trailing slash differs in practice.
    private static func normalizedPath(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? normalizedPath(String(path.dropLast())) : path
    }
}

/// A provider the usage report can show, in the order the report lists them.
enum ReportProvider: String, CaseIterable, Sendable {
    case claude
    case codex

    var usageProvider: UsageProvider {
        switch self {
        case .claude: .claude
        case .codex: .codex
        }
    }

    var name: String { usageProvider.segmentLabel }
}

/// One provider's part of the tokens in All, for the split under the totals.
struct ReportProviderShare: Equatable {
    let provider: ReportProvider
    let tokens: Int
    /// Percent of both providers' tokens.
    let percent: Double
}

/// One project of the report's breakdown, with the providers that worked in it for the logos in All.
struct ReportProjectRow: Identifiable, Equatable, Sendable {
    /// The working directory, or Claude's project key when no transcript named one.
    let id: String
    let name: String
    /// `nil` when only Claude's encoded project key is known, so there is nothing to reveal.
    let path: String?
    let tokens: Int
    let providers: Set<ReportProvider>
    /// Claude's project keys in the row, the keys into `CostSummary.byProject`.
    let claudeKeys: [String]

    func merging(_ other: ReportProjectRow) -> ReportProjectRow {
        ReportProjectRow(
            id: id, name: name, path: path ?? other.path, tokens: tokens + other.tokens,
            providers: providers.union(other.providers), claudeKeys: (claudeKeys + other.claudeKeys).sorted()
        )
    }
}
