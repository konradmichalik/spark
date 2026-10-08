import SwiftUI

/// The report's sections for the selected provider scope (`ReportScoping`): Codex alone has no pace,
/// cost, top lists or cache notes, since only Claude's data has them.
struct ReportBody: View {
    let report: PeriodReport
    let scope: ReportScope
    let codex: CodexReportData?
    let showApiCost: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ReportTotals(report: report, scope: scope, codex: codex, showApiCost: showApiCost)
            if ReportScoping.showsClaudeSections(scope) {
                PaceSection(
                    title: ReportScoping.title("PACE \u{00B7} PEAK PER DAY", scope: scope),
                    days: PaceDaySeries.build(snapshots: state.history, start: report.rangeStart, end: report.rangeEnd),
                    emptyText: report.periodOffset == 0 ? "Not enough data yet." : "No usage history for that period."
                )
            }
            ActivitySection(
                report: report,
                dayTokens: ReportScoping.dayTokens(scope, claude: report.dayTokens, codex: codex?.dayTokens ?? [:])
            )
            HStack(alignment: .top, spacing: 28) {
                ModelShareSection(
                    rows: ReportScoping.modelRows(
                        scope, claude: ModelRow.rows(from: report.modelTotals, costByModel: report.costSummary?.byModel), codex: codex
                    ),
                    emptyText: report.periodOffset == 0 ? "No model usage yet." : "No model usage in that period."
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                if ReportScoping.showsClaudeSections(scope) {
                    ReportList(title: ReportScoping.title("TOP PROJECTS", scope: scope), entries: projects)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            if ReportScoping.showsClaudeSections(scope), !report.topSessions.isEmpty {
                ReportList(title: ReportScoping.title("TOP SESSIONS", scope: scope), entries: sessions)
            }
        }
    }

    @EnvironmentObject private var state: AppState

    private var projects: [ReportEntry] {
        report.topProjects.map { project in
            ReportEntry(
                id: project.key, name: project.displayName, value: formatTokenCount(project.tokens),
                tooltip: StatisticsText.projectTooltip(tokens: project.tokens, cost: report.costSummary?.byProject[project.key]),
                path: project.cwd
            )
        }
    }

    private var sessions: [ReportEntry] {
        report.topSessions.map { session in
            ReportEntry(
                id: session.id, name: session.displayName,
                detail: session.start.map { Self.sessionTiming(start: $0, duration: session.duration) },
                value: formatTokenCount(session.tokens),
                tooltip: StatisticsText.projectTooltip(tokens: session.tokens, cost: report.costSummary?.bySession[session.id])
            )
        }
    }

    /// "Mon 14:20 · 2h 5m". The duration is left out below a minute, where it says nothing.
    private static func sessionTiming(start: Date, duration: TimeInterval?) -> String {
        let startText = start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        guard let duration, duration >= 60 else { return startText }
        return "\(startText) · \(duration.shortDuration)"
    }
}

/// Tokens, the change against the previous period and the API cost estimate, then the notes
/// that qualify them.
private struct ReportTotals: View {
    let report: PeriodReport
    let scope: ReportScope
    let codex: CodexReportData?
    let showApiCost: Bool

    private static let cacheHitRateWarningThreshold = 0.9

    private var totals: ScopedTotals { ReportScoping.totals(scope, report: report, codex: codex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if report.isEmptyWindow {
                // The month started, but its first day has not closed yet: nothing to compare.
                DetailNote(text: "No closed days yet this month.")
            } else {
                HStack(alignment: .top, spacing: 20) {
                    ReportTotal(label: "TOKENS", parts: UsageFormat.tokens(totals.current), tooltip: previousText)
                    trendTotal
                    costTotal
                }
            }
            notes
        }
    }

    private var previousText: String {
        "\(formatTokenCount(totals.previous)) tokens the \(report.period == .month ? "month" : "week") before"
    }

    @ViewBuilder
    private var trendTotal: some View {
        let label = ReportText.comparisonLabel(report.period, start: report.rangeStart)
        if let trend = ReportText.trend(totals.trendPercent) {
            ReportTotal(label: label, parts: trend, tooltip: previousText)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                MicroLabel(text: label)
                DetailNote(text: "No usage to compare with.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var costTotal: some View {
        if ReportScoping.showsClaudeSections(scope), let summary = report.costSummary {
            ReportTotal(
                label: "API COST", parts: UsageFormat.cost(summary.total), prefix: "\u{2248}",
                tooltip: ReportScoping.costTooltip(StatisticsText.costTooltip(summary), scope: scope),
                spokenValue: "about \(formatCost(summary.total))"
            )
        }
    }

    @ViewBuilder
    private var notes: some View {
        if ReportScoping.showsClaudeSections(scope) {
            if report.costSummary == nil, showApiCost {
                DetailNote(text: "API prices unavailable. Check your connection.")
            }
            // Multi-turn use keeps the hit rate near the ceiling, so it only shows when it drops.
            if let rate = report.cacheHitRate, rate < Self.cacheHitRateWarningThreshold {
                WarningBanner(message: "Cache hit rate dropped to \(UsageFormat.percent(rate * 100))")
            }
        }
    }
}
