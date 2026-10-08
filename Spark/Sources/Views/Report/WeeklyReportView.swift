import SwiftUI

/// The usage report window (board 11): a week's or a calendar month's local token usage against
/// the period before it, navigable back one period at a time. Totals, trend and cache hit rate
/// come from the persisted `DailyRollup` data; the model split and top projects from a live scan
/// aligned to the same window; the pace from the polled usage history.
struct WeeklyReportView: View {
    static let windowID = "weeklyReport"

    @EnvironmentObject var state: AppState

    var body: some View {
        // The header stays outside the scroll view: the period controls are what someone reaches
        // for after scrolling down.
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .frame(minHeight: 52)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ScrollView {
                content
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Dims stale numbers while a reopen or period change re-scans.
            .opacity(state.isLoadingWeeklyReport ? 0.5 : 1)
        }
        .frame(minWidth: 460, idealWidth: 560, minHeight: 420, idealHeight: 660)
        .background(Theme.paper)
        .task {
            // Always starts at the current week, so reopening never strands the user on a past
            // period they left the window on.
            state.loadWeeklyReport(period: .week, offset: 0)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let report = state.weeklyReport, report.hasData {
            VStack(alignment: .leading, spacing: 28) {
                ReportTotals(report: report, showApiCost: state.showApiCost)
                PaceSection(
                    days: PaceDaySeries.build(snapshots: state.history, start: report.rangeStart, end: report.rangeEnd),
                    emptyText: report.periodOffset == 0 ? "Not enough data yet." : "No usage history for that period."
                )
                HStack(alignment: .top, spacing: 28) {
                    ModelShareSection(
                        rows: ModelRow.rows(from: report.modelTotals, costByModel: report.costSummary?.byModel),
                        emptyText: report.periodOffset == 0 ? "No model usage yet." : "No model usage in that period."
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    ReportList(title: "TOP PROJECTS", entries: projects(report))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                if !report.topSessions.isEmpty {
                    ReportList(title: "TOP SESSIONS", entries: sessions(report))
                }
            }
        } else if state.weeklyReport == nil {
            // Covers the gap before `.task` fires and the load itself.
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else {
            DetailNote(text: "No usage data yet.")
                .padding(.top, 40)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Usage report")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
            PaperSegments(selection: periodBinding, options: ReportPeriod.allCases, label: "Period")
                .disabled(state.isLoadingWeeklyReport)
            periodNavigator
        }
    }

    private var periodBinding: Binding<ReportPeriod> {
        Binding(get: { state.reportPeriod }, set: { state.loadWeeklyReport(period: $0, offset: 0) })
    }

    private var periodNavigator: some View {
        let noun = state.reportPeriod == .month ? "month" : "week"
        return HStack(spacing: 2) {
            navigationButton(.chevronLeft, label: "Previous \(noun)", enabled: state.canGoToEarlierPeriod, action: state.goToEarlierPeriod)
            Text(periodTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .frame(minWidth: 110)
            navigationButton(.chevronRight, label: "Next \(noun)", enabled: state.canGoToLaterPeriod, action: state.goToLaterPeriod)
        }
    }

    private func navigationButton(_ icon: TablerIcon, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TablerIconView(icon, size: 13, color: Theme.inkSecondary, isDecorative: false)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state.isLoadingWeeklyReport || !enabled)
        .opacity(enabled ? 1 : 0.35)
        .tooltip(label)
        .accessibilityLabel(label)
    }

    private var periodTitle: String {
        guard let report = state.weeklyReport else { return "" }
        return ReportText.periodTitle(report.period, start: report.rangeStart, end: report.rangeEnd)
    }

    private func projects(_ report: PeriodReport) -> [ReportEntry] {
        report.topProjects.map { project in
            ReportEntry(
                id: project.key, name: project.displayName, value: formatTokenCount(project.tokens),
                tooltip: StatisticsText.projectTooltip(tokens: project.tokens, cost: report.costSummary?.byProject[project.key]),
                path: project.cwd
            )
        }
    }

    private func sessions(_ report: PeriodReport) -> [ReportEntry] {
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
    let showApiCost: Bool

    private static let cacheHitRateWarningThreshold = 0.9

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if report.isEmptyWindow {
                // The month started, but its first day has not closed yet: nothing to compare.
                DetailNote(text: "No closed days yet this month.")
            } else {
                HStack(alignment: .top, spacing: 20) {
                    ReportTotal(label: "TOKENS", parts: UsageFormat.tokens(report.currentPeriodTokens), tooltip: previousText)
                    trendTotal
                    costTotal
                }
            }
            notes
        }
    }

    private var previousText: String {
        "\(formatTokenCount(report.previousPeriodTokens)) tokens the \(report.period == .month ? "month" : "week") before"
    }

    @ViewBuilder
    private var trendTotal: some View {
        let label = ReportText.comparisonLabel(report.period, start: report.rangeStart)
        if let trend = ReportText.trend(report.trendPercent) {
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
        if let summary = report.costSummary {
            ReportTotal(
                label: "API COST", parts: UsageFormat.cost(summary.total), prefix: "\u{2248}",
                tooltip: StatisticsText.costTooltip(summary), spokenValue: "about \(formatCost(summary.total))"
            )
        }
    }

    @ViewBuilder
    private var notes: some View {
        if report.costSummary == nil, showApiCost {
            DetailNote(text: "API prices unavailable. Check your connection.")
        }
        // Multi-turn use keeps the hit rate near the ceiling, so it only shows when it drops.
        if let rate = report.cacheHitRate, rate < Self.cacheHitRateWarningThreshold {
            WarningBanner(message: "Cache hit rate dropped to \(UsageFormat.percent(rate * 100))")
        }
    }
}
