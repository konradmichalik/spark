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
            switch provider {
            case .claude: HistoryScreen(history: state.history, rollups: state.rollups)
            case .codex: HistoryScreen(history: codex.history, rollups: [:], showsVolume: false)
            }
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
            LimitsScreen(sections: state.moreLimits, emptyText: state.isLoading ? nil : "No further limits.")
        case .codex:
            LimitsScreen(
                sections: codex.usage.map {
                    AllLimits.codex($0, warning: state.warningThreshold, critical: state.criticalThreshold)
                } ?? LimitSections(limits: [], extras: []),
                emptyText: codex.isLoading ? nil : "No further limits."
            )
        }
    }
}
