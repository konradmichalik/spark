import Foundation

/// The segments of the report's Breakdown screen (docs/design/rules.md, "Windows").
enum ReportBreakdownTab: String, CaseIterable, SegmentLabeled {
    case models = "Models"
    case projects = "Projects"
    case sessions = "Top sessions"

    var segmentLabel: String { rawValue }
}

/// One row of Breakdown, and of the top three on level 1.
struct ReportBreakdownRow: Identifiable, Equatable {
    let id: String
    let name: String
    /// The providers whose logos lead the row, Claude first; empty outside All.
    let providers: [ReportProvider]
    /// The row's share of the scope's total, or a session's start and duration.
    let detail: String
    let tokens: Int
    /// How far the dot bar fills, in percent of the top row.
    let barPercent: Double
    let tooltip: String
    /// The working directory behind a project row, for the folder actions.
    var path: String?
}

/// Turns a scope and the report's data into the rows of each Breakdown tab, so Breakdown and the
/// level 1 lists show the same numbers.
enum ReportBreakdown {
    /// Both providers report their top ten sessions; the merge keeps ten so its order stays exact.
    static let sessionLimit = 10
    /// Level 1 shows this many rows of Models and of Projects.
    static let topCount = 3

    static func rows(
        _ tab: ReportBreakdownTab, scope: ReportScope, report: PeriodReport, codex: CodexReportData?,
        locale: Locale = .current, timeZone: TimeZone = .current
    ) -> [ReportBreakdownRow] {
        let cost = ReportScoping.showsClaudeSections(scope) ? report.costSummary : nil
        switch tab {
        case .models:
            let claude = ModelRow.rows(from: report.modelTotals, costByModel: cost?.byModel)
            return models(scope, claude: claude, codex: codex, locale: locale)
        case .projects:
            return projects(scope, claude: report.topProjects, cost: cost, codex: codex, locale: locale)
        case .sessions:
            return sessions(scope, claude: report.topSessions, cost: cost, codex: codex, locale: locale, timeZone: timeZone)
        }
    }

    static func emptyText(_ tab: ReportBreakdownTab, isCurrentPeriod: Bool) -> String {
        let subject = switch tab {
        case .models: "No model usage"
        case .projects: "No project usage"
        case .sessions: "No sessions"
        }
        return subject + (isCurrentPeriod ? " yet." : " in that period.")
    }

    static func models(_ scope: ReportScope, claude: [ModelRow], codex: CodexReportData?, locale: Locale = .current) -> [ReportBreakdownRow] {
        let rows = ReportScoping.modelRows(scope, claude: claude, codex: codex)
        let total = rows.reduce(0) { $0 + $1.tokens }
        let top = rows.first?.tokens ?? 0
        return rows.map { row in
            ReportBreakdownRow(
                id: row.id, name: row.label, providers: logos(row.providers, scope: scope),
                detail: shareText(row.tokens, of: total, locale: locale), tokens: row.tokens,
                barPercent: StatisticsText.share(row.tokens, of: top), tooltip: row.versionSummary
            )
        }
    }

    static func projects(
        _ scope: ReportScope, claude: [ProjectUsage], cost: CostSummary?, codex: CodexReportData?, locale: Locale = .current
    ) -> [ReportBreakdownRow] {
        let rows = ReportScoping.projectRows(scope, claude: claude, codex: codex)
        let total = rows.reduce(0) { $0 + $1.tokens }
        let top = rows.first?.tokens ?? 0
        return rows.map { row in
            ReportBreakdownRow(
                id: row.id, name: row.name, providers: logos(row.providers, scope: scope),
                detail: shareText(row.tokens, of: total, locale: locale), tokens: row.tokens,
                barPercent: StatisticsText.share(row.tokens, of: top),
                tooltip: projectTooltip(row, cost: scope == .codex ? nil : cost), path: row.path
            )
        }
    }

    static func sessions(
        _ scope: ReportScope, claude: [SessionUsage], cost: CostSummary?, codex: CodexReportData?,
        locale: Locale = .current, timeZone: TimeZone = .current
    ) -> [ReportBreakdownRow] {
        let claudeSessions = scope == .codex ? [] : claude.map { (session: $0, provider: ReportProvider.claude) }
        let codexSessions = scope == .claude ? [] : (codex?.topSessions ?? []).map { (session: $0, provider: ReportProvider.codex) }
        let merged = (claudeSessions + codexSessions)
            .sorted { $0.session.tokens != $1.session.tokens ? $0.session.tokens > $1.session.tokens : $0.session.id < $1.session.id }
            .prefix(sessionLimit)
        let top = merged.first?.session.tokens ?? 0
        return merged.map { session, provider in
            let sessionCost = provider == .claude ? cost?.bySession[session.id] : nil
            return ReportBreakdownRow(
                id: "\(provider.rawValue)-\(session.id)", name: session.displayName, providers: logos([provider], scope: scope),
                detail: session.start.map { sessionTiming(start: $0, duration: session.duration, locale: locale, timeZone: timeZone) } ?? "",
                tokens: session.tokens, barPercent: StatisticsText.share(session.tokens, of: top),
                tooltip: StatisticsText.projectTooltip(tokens: session.tokens, cost: sessionCost)
            )
        }
    }

    /// "Mon 14:20 · 2h 5m". The duration is left out below a minute, where it says nothing.
    static func sessionTiming(start: Date, duration: TimeInterval?, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).hour().minute().locale(locale)
        style.timeZone = timeZone
        let startText = start.formatted(style)
        guard let duration, duration >= 60 else { return startText }
        return "\(startText) \u{00B7} \(duration.shortDuration)"
    }

    /// A share that rounds to nothing still had use, so it reads "<1%" rather than "0%".
    private static func shareText(_ tokens: Int, of total: Int, locale: Locale) -> String {
        let share = StatisticsText.share(tokens, of: total)
        return share > 0 && share < 0.5 ? "<" + UsageFormat.percent(1, locale: locale) : UsageFormat.percent(share, locale: locale)
    }

    private static func logos(_ providers: Set<ReportProvider>, scope: ReportScope) -> [ReportProvider] {
        scope == .all ? ReportProvider.allCases.filter(providers.contains) : []
    }

    /// API cost exists only for Claude's part, so a row Codex also worked in says so.
    private static func projectTooltip(_ row: ReportProjectRow, cost: CostSummary?) -> String {
        let costs = row.claudeKeys.compactMap { cost?.byProject[$0] }
        let projectCost = costs.isEmpty ? nil : costs.reduce(0, +)
        let tooltip = StatisticsText.projectTooltip(tokens: row.tokens, cost: projectCost)
        return projectCost != nil && row.providers.contains(.codex) ? tooltip + ", Claude only" : tooltip
    }
}
