import AppKit
import SwiftUI

/// The popover. Level 1 is the overview of the selected provider; a detail screen replaces the
/// content below the header, which stays put (docs/design/rules.md, "Navigation").
struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var codex: CodexState
    @Environment(\.openWindow) private var openWindow
    @AppStorage(UsageProvider.selectionKey) private var selectedProviderRaw = UsageProvider.claude.rawValue
    @AppStorage("showProviderTabValues") private var showProviderTabValues = true
    @State private var screen: PopoverScreen = .overview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Falls back to Claude whenever Codex is switched off or its sign-in disappears, so a
    /// remembered Codex selection never leaves the popover on an empty tab.
    private var provider: UsageProvider {
        guard codex.isActive else { return .claude }
        return UsageProvider(rawValue: selectedProviderRaw) ?? .claude
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PopoverHeader(
                provider: provider,
                screen: $screen,
                showTabs: codex.isActive,
                tabs: tabs,
                isLoading: isLoading,
                onSelect: select,
                onReport: openReport
            )
            content
                .id(screen)
                // Level 2 pushes in from the right and the overview comes back from the left
                // (docs/design/rules.md, "Motion"). Each screen carries its own edge, so the
                // same transition reads correctly in both directions.
                .transition(
                    reduceMotion
                        ? .identity
                        : .move(edge: screen == .overview ? .leading : .trailing).combined(with: .opacity)
                )
        }
        .clipped()
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: screen)
        .padding(14)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.paper)
        .background(WindowResizer())
        .onAppear { state.startActiveSessionTicker() }
        .onDisappear {
            state.stopActiveSessionTicker()
            // Reopening the popover always starts on the overview.
            screen = .overview
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            if screen == .overview, provider == .claude, !state.isAuthenticated {
                // Without a Claude sign-in the popover still opens, so Codex stays one tab away.
                NotConnectedScreen()
                NotConnectedFooter(codexIsActive: codex.isActive)
            } else if screen == .overview {
                overview
                PopoverFooter(lastUpdated: lastUpdated, isLoading: isLoading, onRefresh: refresh)
            } else {
                DetailScreen(screen: screen, provider: provider)
            }
        }
    }

    @ViewBuilder
    private var overview: some View {
        switch provider {
        case .claude:
            ClaudeOverview { screen = $0 }
        case .codex:
            CodexOverview(
                codex: codex, warning: state.warningThreshold, critical: state.criticalThreshold,
                style: state.usageDisplayStyle, showStats: state.showStats
            ) { screen = $0 }
        }
    }

    /// Switching providers returns to the overview, so a detail screen never shows one
    /// provider's data under the other's breadcrumb.
    private func select(_ provider: UsageProvider) {
        selectedProviderRaw = provider.rawValue
        screen = .overview
    }

    private func openReport() {
        openWindow(id: WeeklyReportView.windowID)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refresh() {
        switch provider {
        case .claude: Task { await state.fetchUsage() }
        case .codex: Task { await codex.fetchUsage(force: true) }
        }
    }

    private var tabs: [ProviderTab] {
        UsageProvider.allCases.map { provider in
            let value = showProviderTabValues
                ? MenuBarReading.providerValue(for: provider, claude: state.usageData, codex: codex.usage, mode: "session")
                : nil
            return ProviderTab(
                provider: provider,
                value: value,
                tone: UsageTone(value: value ?? 0, warning: state.warningThreshold, critical: state.criticalThreshold),
                tooltip: tabTooltip(provider)
            )
        }
    }

    private func tabTooltip(_ provider: UsageProvider) -> String? {
        switch provider {
        case .claude:
            ProviderTabSummary.tooltip(plan: state.accountTier.displayName, signIn: "via \(state.authMethod.rawValue)")
        case .codex:
            ProviderTabSummary.tooltip(plan: codex.usage.map { "ChatGPT \($0.planDisplayName)" }, signIn: "via Codex CLI")
        }
    }

    private var isLoading: Bool {
        provider == .codex ? codex.isLoading : state.isLoading
    }

    private var lastUpdated: Date {
        guard provider == .codex else { return state.usageData.lastUpdated }
        return codex.usage?.usageData.lastUpdated ?? .distantPast
    }
}
