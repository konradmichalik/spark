import SwiftUI

/// A dedicated window (opened alongside Settings) summarizing a week's or a calendar month's
/// local token usage against the period before it, navigable back one period at a time. The
/// headline totals, trend, and cache hit rate come from the same persisted `DailyRollup` data
/// the Volume chart uses; the model split and top projects come from a live scan aligned to the
/// same window.
struct WeeklyReportView: View {
    static let windowID = "weeklyReport"

    @EnvironmentObject var state: AppState

    private let density = SectionDensity.compact

    var body: some View {
        // `header` (period picker + prev/next controls) stays outside the ScrollView — those are
        // exactly the controls someone reaches for after scrolling down, and a control that
        // disappears when you scroll toward the content it affects is a bad place to put it.
        VStack(alignment: .leading, spacing: 16) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let report = state.weeklyReport, report.hasData {
                        totalsSection(report)
                        paceSection(report)
                        modelSplitSection(report)
                        if !report.topProjects.isEmpty {
                            topProjectsSection(report)
                        }
                    } else if state.weeklyReport == nil {
                        // Covers both the gap before `.task` fires and the load itself — the
                        // request never resolves to an empty report, only to nil-until-loaded or
                        // a real one.
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else {
                        Text("No usage data yet.")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    }
                }
            }
        }
        .padding(20)
        // A fixed ideal size for the window to open at, tall enough that the common case (every
        // section present, including the cache-hit-rate warning) fits without scrolling;
        // `.windowResizability(.contentMinSize)` (set on the `Window` scene) lets the user grow
        // it further, and the `ScrollView` above means content taller than this (e.g. a long
        // project name wrapping, or the user shrinking the window back down) scrolls instead of
        // clipping at the minimum size.
        .frame(minWidth: 340, idealWidth: 360, minHeight: 380, idealHeight: 700)
        // Dims stale numbers while a reopen or period change re-scans, instead of showing them
        // un-dimmed.
        .opacity(state.isLoadingWeeklyReport ? 0.5 : 1)
        .task {
            // Always starts back at the current week, so navigating away and reopening never
            // strands the user on a past period they left the window on.
            state.loadWeeklyReport(period: .week, offset: 0)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                TablerIconView(.calendarMonth, color: .secondary)
                Text("Usage Report")
                    .font(.custom("InstrumentSerif-Regular", size: 15))
                Spacer()
                SegmentPicker(selection: periodBinding, options: ReportPeriod.allCases)
                    .disabled(state.isLoadingWeeklyReport)
            }
            periodNavigator
        }
    }

    private var periodBinding: Binding<ReportPeriod> {
        Binding(get: { state.reportPeriod }, set: { state.loadWeeklyReport(period: $0, offset: 0) })
    }

    private var periodNavigator: some View {
        HStack {
            Button {
                state.goToEarlierPeriod()
            } label: {
                TablerIconView(.chevronLeft, size: 11)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(state.isLoadingWeeklyReport || !state.canGoToEarlierPeriod)
            .help("Previous \(state.reportPeriod == .month ? "month" : "week")")
            .accessibilityLabel("Previous \(state.reportPeriod == .month ? "month" : "week")")

            Spacer()
            Text(periodLabel)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            Spacer()

            Button {
                state.goToLaterPeriod()
            } label: {
                TablerIconView(.chevronRight, size: 11)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(state.isLoadingWeeklyReport || !state.canGoToLaterPeriod)
            .help("Next \(state.reportPeriod == .month ? "month" : "week")")
            .accessibilityLabel("Next \(state.reportPeriod == .month ? "month" : "week")")
        }
    }

    /// The shown range's own label is the single place it's stated — `totalsSection`
    /// deliberately doesn't repeat it.
    private var periodLabel: String {
        guard let report = state.weeklyReport else { return "" }
        switch report.period {
        case .week:
            if report.periodOffset == 0 { return "This Week" }
            let style = Date.FormatStyle().month(.abbreviated).day()
            return "\(report.rangeStart.formatted(style)) – \(report.rangeEnd.formatted(style))"
        case .month:
            if report.periodOffset == 0 { return "This Month" }
            return report.rangeStart.formatted(Date.FormatStyle().month(.wide).year())
        }
    }

    private func totalsSection(_ report: PeriodReport) -> some View {
        let periodNoun = report.period == .month ? "month" : "week"

        return VStack(alignment: .leading, spacing: density.headerGap) {
            SectionHeader("Totals", icon: .reportAnalytics, density: density)
            SectionCard(density: density) {
                if report.isEmptyWindow {
                    // The current month started, but its first day hasn't closed yet — there is
                    // nothing to compare against, so skip the trend badge entirely rather than
                    // showing a misleading "0 tokens, down 100%".
                    Text("No closed days yet this month")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(formatTokenCount(report.currentPeriodTokens))
                            .font(.system(.title2, design: .monospaced))
                            .fontWeight(.semibold)
                        if let trend = report.trendPercent {
                            TrendBadge(percent: trend, comparisonNoun: periodNoun)
                        }
                    }
                    Text("tokens vs. \(formatTokenCount(report.previousPeriodTokens)) the \(periodNoun) before")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            // Active multi-turn usage re-sends its whole growing context every turn, so the hit
            // rate sits near-ceiling (95-99%+) almost all the time — showing it unconditionally
            // would just be noise. Surfacing it only below the threshold turns it into a warning
            // for when something (e.g. an unstable prompt prefix) actually broke the caching.
            if let cacheHitRate = report.cacheHitRate, cacheHitRate < Self.cacheHitRateWarningThreshold {
                WarningBanner(message: "Cache hit rate dropped to \(Int((cacheHitRate * 100).rounded()))%")
            }
        }
    }

    private static let cacheHitRateWarningThreshold = 0.9

    /// Session (5h) and Weekly quota utilization over the shown period, with day ticks and a
    /// hover readout. Sourced from the polled `UsageSnapshot` history, the same data the
    /// popover's Limits graph draws from, filtered to the shown period's calendar days.
    private func paceSection(_ report: PeriodReport) -> some View {
        let days = paceDays(for: report)
        let hasAnyPaceData = days.contains(where: \.hasData)

        return VStack(alignment: .leading, spacing: density.headerGap) {
            SectionHeader("Pace", icon: .chartLine, density: density)
            SectionCard(density: density) {
                if !hasAnyPaceData {
                    Text(report.periodOffset == 0 ? "Not enough data yet" : "No usage history for that period")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    PaceGraph(days: days)
                }
            }
        }
    }

    /// One point per calendar day (see `PaceDaySeries`) rather than every raw poll — plotting
    /// each of potentially thousands of samples was both too dense to read and, since `days` is
    /// recomputed on every `body` pass, too slow to redraw on hover.
    private func paceDays(for report: PeriodReport) -> [PaceDay] {
        PaceDaySeries.build(snapshots: state.history, start: report.rangeStart, end: report.rangeEnd)
    }

    private func modelSplitSection(_ report: PeriodReport) -> some View {
        let rows = ModelRow.rows(from: report.modelTotals)

        return VStack(alignment: .leading, spacing: density.headerGap) {
            SectionHeader("By Model", icon: .chartBar, density: density)
            SectionCard(density: density) {
                if rows.isEmpty {
                    Text(report.periodOffset == 0 ? "No model usage yet" : "No model usage in that period")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    HStack(spacing: 16) {
                        ModelDonutChart(rows: rows)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(rows) { row in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(row.color)
                                        .frame(width: 8, height: 8)
                                    Text(row.label)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(formatTokenCount(row.tokens))
                                        .font(.system(.caption, design: .monospaced))
                                        .fontWeight(.medium)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func topProjectsSection(_ report: PeriodReport) -> some View {
        VStack(alignment: .leading, spacing: density.headerGap) {
            SectionHeader("Top Projects", icon: .layoutGrid, density: density)
            SectionCard(density: density) {
                ForEach(report.topProjects) { project in
                    HStack {
                        Text(project.displayName)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(formatTokenCount(project.tokens))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}
