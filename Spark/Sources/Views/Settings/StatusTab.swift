import SwiftUI

struct StatusTab: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var codex: CodexState

    var body: some View {
        SettingsPage {
            SettingsSection(
                title: "Claude services",
                footnote: "Live status from the Anthropic status page. The popover only mentions it during an incident."
            ) {
                overallCard(
                    dot: state.status.dot, description: state.statusDescription, provider: "Claude",
                    page: "status.claude.com", refresh: { await state.fetchStatus() }
                )
            }

            if !state.components.isEmpty {
                SettingsSection(title: "Components") {
                    componentCard(state.components.map { CodexStatusComponent(name: $0.name, status: $0.status) })
                }
            }

            if codex.isActive {
                SettingsSection(
                    title: "Codex services",
                    footnote: "Live status from the OpenAI status page, limited to the Codex components."
                ) {
                    overallCard(
                        dot: codex.status.overall.dot, description: codex.status.description, provider: "Codex",
                        page: "status.openai.com", refresh: { await codex.fetchStatus() }
                    )
                }

                if !codex.status.components.isEmpty {
                    SettingsSection(title: "Codex components") {
                        componentCard(codex.status.components)
                    }
                }
            }
        }
    }

    private func overallCard(
        dot: StatusDot, description: String, provider: String, page: StaticString, refresh: @escaping () async -> Void
    ) -> some View {
        SettingsCard {
            HStack(spacing: 10) {
                StatusDotView(dot: dot, size: 15)
                Text(description)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button {
                    Task { await refresh() }
                } label: {
                    TablerIconView(.refresh, size: 13, color: Theme.inkSecondary, isDecorative: false)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tooltip("Refresh")
                .accessibilityLabel("Refresh \(provider) service status")
                Link(destination: URL(staticString: page)) {
                    TablerIconView(.externalLink, size: 13, color: Theme.inkSecondary, isDecorative: false)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tooltip("Open \(page)")
                .accessibilityLabel("Open \(provider) status page")
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
        }
    }

    private func componentCard(_ components: [CodexStatusComponent]) -> some View {
        SettingsCard {
            ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                if index > 0 { SettingsDivider() }
                componentRow(component)
            }
        }
    }

    /// A component in trouble gets an ochre icon; its status is spelled out in ink beside it.
    private func componentRow(_ component: CodexStatusComponent) -> some View {
        HStack(spacing: 8) {
            StatusDotView(dot: component.status.dot, size: 13, healthyColor: Theme.inkTertiary)
            Text(component.name)
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(component.status.displayName)
                .font(.system(size: 12, weight: component.status.isHealthy ? .regular : .semibold))
                .foregroundStyle(component.status.isHealthy ? Theme.inkSecondary : Theme.ink)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .accessibilityElement(children: .combine)
    }
}
