import SwiftUI

/// The second level of the popover. In this phase each screen hosts the views that used to sit
/// on the first level, unchanged; phase 4 of the redesign restyles them.
struct DetailScreen: View {
    let screen: PopoverScreen
    let provider: UsageProvider

    @EnvironmentObject var state: AppState
    @EnvironmentObject var codex: CodexState

    var body: some View {
        switch screen {
        case .overview:
            EmptyView()
        case .history:
            HistoryScreen(history: state.history, rollups: state.rollups)
        case .sessions:
            SessionsScreen(sessions: state.activeSessions)
        case .statistics:
            statistics
        case .limits:
            limits
        }
    }

    @ViewBuilder
    private var statistics: some View {
        switch provider {
        case .claude: ClaudeStatisticsScreen()
        case .codex: CodexStatisticsScreen(codex: codex)
        }
    }

    @ViewBuilder
    private var limits: some View {
        switch provider {
        case .claude:
            ClaudeLimitsList()
        case .codex:
            CodexLimitsList(codex: codex, warningThreshold: state.warningThreshold, criticalThreshold: state.criticalThreshold)
        }
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Every Claude limit for the "All limits" screen: session, week, the per-model weeks the user
/// enabled, and extra usage. Moved unchanged from the former Usage section.
struct ClaudeLimitsList: View {
    @EnvironmentObject var state: AppState

    private static let fiveHours: TimeInterval = 5 * 3600
    private static let sevenDays: TimeInterval = 7 * 24 * 3600

    var body: some View {
        SectionCard(density: .compact) {
            if let session = state.usageData.session {
                UsageRow(
                    label: "Session (5h)",
                    utilization: session.utilization,
                    resetTime: session.timeUntilReset,
                    resetDate: session.resetsAtDate,
                    warningThreshold: state.warningThreshold,
                    criticalThreshold: state.criticalThreshold,
                    pace: Pace.calculate(utilization: session.utilization, resetsAt: session.resetsAtDate, windowLength: Self.fiveHours)
                )
            }
            if let weekly = state.usageData.weekly {
                weeklyRow("Weekly (7 days)", weekly, localTokens: nil)
            }
            if state.showSonnetUsage { modelRow("Sonnet", state.usageData.weeklySonnet, family: .sonnet) }
            if state.showOpusUsage { modelRow("Opus", state.usageData.weeklyOpus, family: .opus) }
            if state.showFableUsage { modelRow("Fable", state.usageData.weeklyFable, family: .fable) }
            extraUsageRow
            if state.usageData.session == nil, state.lastError == nil, !state.isLoading {
                Text("No data available")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
    }

    private func weeklyRow(_ label: String, _ bucket: UsageBucket, localTokens: String?) -> some View {
        UsageRow(
            label: label,
            utilization: bucket.utilization,
            resetTime: bucket.timeUntilReset,
            resetDate: bucket.resetsAtDate,
            warningThreshold: state.warningThreshold,
            criticalThreshold: state.criticalThreshold,
            localTokens: localTokens,
            pace: Pace.calculate(utilization: bucket.utilization, resetsAt: bucket.resetsAtDate, windowLength: Self.sevenDays)
        )
    }

    /// `bucket` is nil when the plan has no quota for that model; local token attribution still
    /// exists independently, so it is shown as a plain line instead of an empty 0% bar.
    @ViewBuilder
    private func modelRow(_ name: String, _ bucket: UsageBucket?, family: ModelFamily) -> some View {
        let localTokens = (state.liveStats?.tokens(for: family)).flatMap { $0 > 0 ? formatTokenCount($0) : nil }
        if let bucket {
            weeklyRow("\(name) (Weekly)", bucket, localTokens: localTokens)
        } else if let localTokens {
            LocalOnlyUsageRow(label: name, localTokens: localTokens)
        }
    }

    @ViewBuilder
    private var extraUsageRow: some View {
        if let extra = state.usageData.extraUsage, extra.hasSpend, let spend = extra.formattedSpendWithLimit {
            HStack(spacing: 6) {
                TablerIconView(.circlePlus, size: 11)
                Text("Extra usage")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(spend)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Extra usage \(extra.spendAccessibilityValue ?? spend)")
        }
    }
}
