import SwiftUI

/// The second level of the popover: one detail screen of the selected provider below the
/// breadcrumb (docs/design/rules.md, "Navigation").
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
            switch provider {
            case .claude: ClaudeStatisticsScreen()
            case .codex: CodexStatisticsScreen(codex: codex)
            }
        case .limits:
            limits
        }
    }

    @ViewBuilder
    private var limits: some View {
        switch provider {
        case .claude:
            LimitsScreen(
                plan: state.accountTier.displayName,
                sections: AllLimits.claude(
                    state.usageData, models: claudeModels, localTokens: claudeLocalTokens,
                    warning: state.warningThreshold, critical: state.criticalThreshold
                ),
                emptyText: state.isLoading ? nil : "No data available"
            )
        case .codex:
            LimitsScreen(
                plan: codex.usage?.planDisplayName.map { "ChatGPT \($0)" },
                sections: codex.usage.map {
                    AllLimits.codex($0, warning: state.warningThreshold, critical: state.criticalThreshold)
                } ?? LimitSections(limits: [], extras: []),
                emptyText: codex.isLoading ? nil : codex.usage.map { HeadlineLimit.emptyText(limitReached: $0.limitReached) } ?? "No data available"
            )
        }
    }

    private var claudeModels: [ModelFamily] {
        [(ModelFamily.sonnet, state.showSonnetUsage), (.opus, state.showOpusUsage), (.fable, state.showFableUsage)]
            .filter(\.1)
            .map(\.0)
    }

    private var claudeLocalTokens: [ModelFamily: Int] {
        guard let live = state.liveStats else { return [:] }
        return Dictionary(uniqueKeysWithValues: claudeModels.map { ($0, live.tokens(for: $0)) })
    }
}
