import SwiftUI

/// The report's first card (docs/design/rules.md, "Windows", Totals card): Tokens with the
/// comparison and the average per active day under it, Sessions and API cost beside it, the
/// provider split in All, and the notes that qualify the numbers.
struct ReportTotalsCard: View {
    @EnvironmentObject private var state: AppState
    let report: PeriodReport
    let scope: ReportScope
    let codex: CodexReportData?
    let showApiCost: Bool
    /// The scope's fresh tokens per day, rolled-up days included, for the average per active day.
    let dayTokens: [String: Int]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cacheHitRateWarningThreshold = 0.9
    private static let sideWidth: CGFloat = 150

    private var totals: ScopedTotals { ReportScoping.totals(scope, report: report, codex: codex) }

    var body: some View {
        ReportCard {
            VStack(alignment: .leading, spacing: 14) {
                if report.isEmptyWindow {
                    // The month started, but its first day has not closed yet: nothing to compare.
                    DetailNote(text: "No closed days yet this month.")
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        tokens
                        Rectangle().fill(Theme.hairline).frame(width: 1)
                        VStack(alignment: .leading, spacing: 14) {
                            sessions
                            if showApiCost { apiCost }
                        }
                        .frame(width: Self.sideWidth, alignment: .leading)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    if scope == .all {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                        ReportProviderSplit(shares: ReportScoping.providerSplit(report: report, codex: codex))
                    }
                }
                cacheWarning
            }
        }
    }

    private var tokens: some View {
        let parts = UsageFormat.tokens(totals.current)
        return VStack(alignment: .leading, spacing: 6) {
            MicroLabel(text: "TOKENS")
            DotoValue(parts: parts, size: ReportLayout.tokensSize(parts.number))
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: totals.current)
                .contentShape(Rectangle())
                .tooltip(tokenDefinition, title: "TOKENS", delay: .quick)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Tokens")
                .accessibilityValue("\(parts.number)\(parts.unit)")
                .accessibilityHint(tokenDefinition)
            noteLine(comparison, tooltip: previousTokens)
            if let average = ReportText.dailyAverage(
                total: totals.current, activeDays: ReportScoping.activeDays(dayTokens, from: report.rangeStart, to: report.rangeEnd)
            ) {
                noteLine(average)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tokenDefinition: String {
        switch scope {
        case .claude: TokenWording.claude
        case .codex: TokenWording.codex
        case .all: TokenWording.both
        }
    }

    private var comparison: String {
        ReportText.comparison(
            totals.trendPercent, period: report.period, previousStart: report.previousStart,
            previousEnd: report.comparesPartOfMonth ? report.previousEnd : nil
        ) ?? "No usage to compare with."
    }

    private var previousTokens: String? {
        guard totals.previous > 0 else { return nil }
        return ReportText.previousTokens(
            totals.previous, period: report.period, partialDays: report.comparesPartOfMonth ? report.previousDayCount() : nil
        )
    }

    private func noteLine(_ text: String, tooltip: String? = nil) -> some View {
        Text(text)
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
            .tooltip(tooltip, delay: .quick)
            .accessibilityHint(tooltip ?? "")
    }

    private var sessions: some View {
        let count = ReportScoping.sessionCount(scope, report: report, codex: codex)
        return ReportFigure(label: "SESSIONS", tooltip: "Sessions with activity in this period.", spoken: String(count)) {
            DotoValue(parts: UsageFormat.count(count), size: 28)
        }
    }

    /// API cost keeps its slot in every scope; without a value it says why.
    @ViewBuilder
    private var apiCost: some View {
        let note = ReportScoping.costNote(scope)
        if scope != .codex, let summary = report.costSummary {
            let tooltip = ReportScoping.costTooltip(
                StatisticsText.planPriceHint(
                    StatisticsText.costTooltip(summary, planValue: planValue(summary)), planPrice: state.monthlyPlanPrice
                ),
                scope: scope
            )
            ReportFigure(
                label: "API COST", tooltip: tooltip,
                spoken: ["about \(formatCost(summary.total))", note].compactMap { $0 }.joined(separator: ", ")
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    DotoValue(parts: UsageFormat.cost(summary.total), prefix: "\u{2248}", size: 28)
                    if let note { DetailNote(text: note) }
                }
            }
        } else {
            let reason = scope == .codex ? note ?? "" : "API prices unavailable. Check your connection."
            ReportFigure(label: "API COST", spoken: reason) {
                DetailNote(text: reason)
            }
        }
    }

    private func planValue(_ summary: CostSummary) -> PlanValue? {
        PlanValue(
            apiCost: summary.total, monthlyPrice: state.monthlyPlanPrice, days: report.costDayCount(),
            extraSpend: state.extraUsageSpend(in: report.costWindow())
        )
    }

    /// Multi-turn use keeps the hit rate near the ceiling, so it only shows when it drops.
    @ViewBuilder
    private var cacheWarning: some View {
        if ReportScoping.showsClaudeSections(scope), let rate = report.cacheHitRate, rate < Self.cacheHitRateWarningThreshold {
            let previous = report.previousCacheHitRate.flatMap { $0 > rate ? $0 : nil }
            let was = previous.map { " (was \(UsageFormat.percent($0 * 100)))" } ?? ""
            WarningBanner(message: "Cache hit rate dropped to \(UsageFormat.percent(rate * 100))\(was)")
        }
    }
}

/// All's tokens split into Claude (ink) and Codex (ink at 45 %) as one dot bar that fills from the
/// left on appear, with name, tokens and share of each under it.
struct ReportProviderSplit: View {
    let shares: [ReportProviderShare]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ReportSplitBar(
                claudePercent: shares.first { $0.provider == .claude }?.percent ?? 0,
                hasUse: shares.contains { $0.tokens > 0 }
            )
            .frame(height: 6)
            HStack(spacing: 16) {
                ForEach(shares, id: \.provider) { item($0) }
                Spacer(minLength: 0)
            }
        }
    }

    private func item(_ share: ReportProviderShare) -> some View {
        HStack(spacing: 5) {
            Circle().fill(ReportSplitBar.colour(share.provider)).frame(width: 6, height: 6)
            Text(share.provider.name)
                .foregroundStyle(Theme.ink)
            Text("\(formatTokenCount(share.tokens)) \u{00B7} \(UsageFormat.percent(share.percent))")
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
        }
        .font(.system(size: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(share.provider.name)
        .accessibilityValue("\(formatTokenCount(share.tokens)) tokens, \(UsageFormat.percent(share.percent))")
    }
}

private struct ReportSplitBar: View {
    let claudePercent: Double
    let hasUse: Bool

    private static let pitch: CGFloat = 4
    private static let dotSize: CGFloat = 2.6

    static func colour(_ provider: ReportProvider) -> Color {
        provider == .claude ? Theme.ink : Theme.ink.opacity(0.45)
    }

    var body: some View {
        let value: Double = hasUse ? 100 : 0
        DotMotion(value: value, animates: true) { frame in
            Canvas { context, size in
                let layout = DotBarLayout(count: DotBarLayout.count(width: size.width, pitch: Self.pitch), value: value)
                let claudeDots = Int((Double(layout.dots.count) * claudePercent / 100).rounded())
                for (position, dot) in frame.dots(of: layout).enumerated() {
                    let colour = dot != .filled ? Theme.dotTrack : Self.colour(position < claudeDots ? .claude : .codex)
                    let centerX = Self.pitch * CGFloat(position) + Self.pitch / 2
                    let rect = CGRect(x: centerX - Self.dotSize / 2, y: size.height / 2 - Self.dotSize / 2, width: Self.dotSize, height: Self.dotSize)
                    context.fill(Path(ellipseIn: rect), with: .color(colour))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
