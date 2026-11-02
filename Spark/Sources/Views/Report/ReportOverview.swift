import SwiftUI

/// Level 1 of the usage report: how much and where it went, in this order: totals, Activity,
/// Limits, then Models and Projects side by side (docs/design/rules.md, "Windows"). Every card
/// but the totals opens its level 2 screen.
struct ReportOverview: View {
    let report: PeriodReport
    let scope: ReportScope
    let codex: CodexReportData?
    let series: ReportDaySeries
    /// One per provider in the scope, Claude first.
    let limits: [ReportLimits]
    /// The scope's fresh tokens per day, rolled-up days included.
    let dayTokens: [String: Int]
    let showApiCost: Bool
    let open: (ReportScreen) -> Void
    let openBreakdown: (ReportBreakdownTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReportTotalsCard(report: report, scope: scope, codex: codex, showApiCost: showApiCost, dayTokens: dayTokens)
            ReportCardButton(title: "Activity", label: ReportCardText.activity(series)) { open(.activity) } content: {
                VStack(alignment: .leading, spacing: 10) {
                    ReportDayColumns(series: series, scope: scope, period: report.period)
                    Text(ReportDayText.overviewLine(series, calendar: .current))
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if scope == .all { ReportProviderLegend() }
                }
            }
            ReportCardButton(title: "Limits", label: ReportCardText.limits(limits)) { open(.limits) } content: {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(limits, id: \.provider) { ReportOverviewLimitRow(limits: $0) }
                }
            }
            // Both cards are as tall as the taller one.
            HStack(alignment: .top, spacing: 12) {
                breakdownCard(.models)
                breakdownCard(.projects)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func breakdownCard(_ tab: ReportBreakdownTab) -> some View {
        let rows = ReportBreakdown.rows(tab, scope: scope, report: report, codex: codex)
        return ReportCardButton(title: tab.segmentLabel, label: ReportCardText.breakdown(tab, rows: rows)) {
            openBreakdown(tab)
        } content: {
            ReportTopList(rows: rows, emptyText: ReportBreakdown.emptyText(tab, isCurrentPeriod: report.periodOffset == 0))
        }
    }
}

/// A level 1 card that opens a level 2 screen: a sentence-case title and a chevron over its
/// content. The whole card is the hit target and one element for VoiceOver.
struct ReportCardButton<Content: View>: View {
    let title: String
    /// What the card opens plus its key figure (`ReportCardText`).
    let label: String
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            ReportCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.inkSecondary)
                        Spacer(minLength: 8)
                        TablerIconView(.chevronRight, size: 11, color: Theme.inkTertiary)
                    }
                    content()
                }
                // Side by side, the shorter card stretches to the taller one.
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// One provider on the Limits card: logo and name, the weekly line, and the short summary.
private struct ReportOverviewLimitRow: View {
    let limits: ReportLimits

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                PopoverHeader.logo(for: limits.provider.usageProvider)
                Text(limits.provider.name)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: 72, alignment: .leading)
            if limits.hasHistory {
                ReportLimitSparkline(days: limits.days)
            } else {
                Spacer(minLength: 0)
            }
            Text(limits.summary)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(minHeight: 28)
    }
}
