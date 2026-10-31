import SwiftUI

/// The report's sections for the selected provider scope (`ReportScoping`): Claude-specific pace,
/// cost and cache notes stay hidden for Codex, which has its own top-project list.
struct ReportBody: View {
    let report: PeriodReport
    let scope: ReportScope
    let codex: CodexReportData?
    let showApiCost: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReportCard {
                ReportTotals(
                    report: report, scope: scope, codex: codex, showApiCost: showApiCost,
                    monthlyPlanPrice: state.monthlyPlanPrice, dayTokens: persistedDayTokens
                )
            }
            if ReportScoping.showsClaudeSections(scope) {
                ReportCard {
                    PaceSection(
                        title: ReportScoping.title("PACE \u{00B7} PEAK PER DAY", scope: scope),
                        days: PaceDaySeries.build(snapshots: state.history, start: report.rangeStart, end: report.rangeEnd),
                        emptyText: report.periodOffset == 0 ? "Not enough data yet." : "No usage history for that period."
                    )
                }
            }
            ReportCard {
                ActivitySection(report: report, dayTokens: scopedDayTokens)
            }
            if let weekdays = WeekdayProfile.make(dayTokens: persistedDayTokens, start: report.rangeStart, end: report.rangeEnd) {
                ReportCard {
                    WeekdaySection(profile: weekdays)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                ReportCard {
                    ModelShareSection(
                        rows: ReportScoping.modelRows(
                            scope, claude: ModelRow.rows(from: report.modelTotals, costByModel: report.costSummary?.byModel), codex: codex
                        ),
                        emptyText: report.periodOffset == 0 ? "No model usage yet." : "No model usage in that period."
                    )
                }
                if ReportScoping.showsClaudeSections(scope) || !projectEntries.isEmpty {
                    ReportCard {
                        ReportList(title: ReportScoping.title("TOP PROJECTS", scope: scope), entries: projectEntries)
                    }
                }
            }
            // Both cards in the row are as tall as the taller one.
            .fixedSize(horizontal: false, vertical: true)
            if ReportScoping.showsClaudeSections(scope), !report.topSessions.isEmpty {
                ReportCard {
                    ReportList(title: ReportScoping.title("TOP SESSIONS", scope: scope), entries: sessions)
                }
            }
        }
    }

    @EnvironmentObject private var state: AppState

    private var scopedDayTokens: [String: Int] {
        ReportScoping.dayTokens(scope, claude: report.dayTokens, codex: codex?.dayTokens ?? [:])
    }

    /// For the figures that divide the rollup totals, which reach back further than the transcripts.
    private var persistedDayTokens: [String: Int] {
        let claude = ReportScoping.persistedDayTokens(rollups: state.rollups, live: report.dayTokens)
        return ReportScoping.dayTokens(scope, claude: claude, codex: codex?.dayTokens ?? [:])
    }

    private var projects: [ReportEntry] {
        report.topProjects.map { project in
            ReportEntry(
                id: project.key, name: project.displayName, value: formatTokenCount(project.tokens),
                tooltip: StatisticsText.projectTooltip(tokens: project.tokens, cost: report.costSummary?.byProject[project.key]),
                path: project.cwd
            )
        }
    }

    private var codexProjects: [ReportEntry] {
        let projects = ReportScoping.projectTokens(scope, claude: [:], codex: codex)
        return StatisticsText.rankedProjects(projects).map { project in
            ReportEntry(
                id: project.path, name: ProjectFamily.displayName(forKey: project.path, cwd: project.path),
                value: formatTokenCount(project.tokens), tooltip: "\(formatTokenCount(project.tokens)) tokens",
                path: project.path
            )
        }
    }

    private var projectEntries: [ReportEntry] {
        scope == .codex ? codexProjects : projects
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
    let monthlyPlanPrice: Double?
    let dayTokens: [String: Int]

    private static let cacheHitRateWarningThreshold = 0.9

    private var totals: ScopedTotals { ReportScoping.totals(scope, report: report, codex: codex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if report.isEmptyWindow {
                // The month started, but its first day has not closed yet: nothing to compare.
                DetailNote(text: "No closed days yet this month.")
            } else {
                HStack(alignment: .top, spacing: 20) {
                    ReportTotal(label: "TOKENS", parts: UsageFormat.tokens(totals.current), tooltip: previousText, size: totalsSize)
                    trendTotal
                    costTotal
                }
                if let average = dailyAverage {
                    DetailNote(text: average)
                }
            }
            notes
        }
    }

    private var dailyAverage: String? {
        ReportText.dailyAverage(
            total: totals.current, activeDays: ReportScoping.activeDays(dayTokens, from: report.rangeStart, to: report.rangeEnd)
        )
    }

    private var costSummary: CostSummary? {
        ReportScoping.showsClaudeSections(scope) ? report.costSummary : nil
    }

    /// The three totals share one size, set by the longest of them.
    private var totalsSize: CGFloat {
        let values = [
            UsageFormat.tokens(totals.current).number,
            ReportText.trend(totals.trendPercent)?.number,
            costSummary.map { "\u{2248}" + UsageFormat.cost($0.total).number }
        ]
        return ReportLayout.totalsSize(values.compactMap { $0 })
    }

    private var previousText: String {
        let tokens = formatTokenCount(totals.previous)
        if report.comparesPartOfMonth {
            let days = report.previousDayCount()
            return "\(tokens) tokens in the first \(days) \(days == 1 ? "day" : "days") of the month before"
        }
        return "\(tokens) tokens the \(report.period == .month ? "month" : "week") before"
    }

    @ViewBuilder
    private var trendTotal: some View {
        let label = ReportText.comparisonLabel(
            report.period, previousStart: report.previousStart, previousEnd: report.comparesPartOfMonth ? report.previousEnd : nil
        )
        if let trend = ReportText.trend(totals.trendPercent) {
            ReportTotal(label: label, parts: trend, tooltip: previousText, size: totalsSize)
        } else {
            ReportFigure(label: label, spoken: "No usage to compare with.") {
                DetailNote(text: "No usage to compare with.")
            }
        }
    }

    @ViewBuilder
    private var costTotal: some View {
        if ReportScoping.showsClaudeSections(scope), let summary = report.costSummary {
            ReportTotal(
                label: "API COST", parts: UsageFormat.cost(summary.total), prefix: "\u{2248}",
                tooltip: ReportScoping.costTooltip(StatisticsText.costTooltip(summary, planValue: planValue(summary)), scope: scope),
                spokenValue: "about \(formatCost(summary.total))", size: totalsSize
            )
        }
    }

    private func planValue(_ summary: CostSummary) -> PlanValue? {
        PlanValue(apiCost: summary.total, monthlyPrice: monthlyPlanPrice, days: report.costDayCount())
    }

    @ViewBuilder
    private var notes: some View {
        if ReportScoping.showsClaudeSections(scope) {
            if report.costSummary == nil, showApiCost {
                DetailNote(text: "API prices unavailable. Check your connection.")
            }
            // Multi-turn use keeps the hit rate near the ceiling, so it only shows when it drops.
            if let rate = report.cacheHitRate, rate < Self.cacheHitRateWarningThreshold {
                let previous = report.previousCacheHitRate.flatMap { $0 > rate ? $0 : nil }
                let was = previous.map { " (was \(UsageFormat.percent($0 * 100)))" } ?? ""
                WarningBanner(message: "Cache hit rate dropped to \(UsageFormat.percent(rate * 100))\(was)")
            }
        }
    }
}
