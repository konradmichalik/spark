import SwiftUI

struct StatusTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        SettingsPage {
            SettingsSection(
                title: "Claude services",
                footnote: "Live status from the Anthropic status page. The popover only mentions it during an incident."
            ) {
                SettingsCard {
                    HStack(spacing: 10) {
                        DotIconView(icon: state.status.dotIcon, size: 15, color: statusColor(state.status, healthy: Theme.ink))
                        Text(state.statusDescription)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Button {
                            Task { await state.fetchStatus() }
                        } label: {
                            TablerIconView(.refresh, size: 13, color: Theme.inkSecondary, isDecorative: false)
                                .frame(width: 26, height: 26)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .tooltip("Refresh")
                        .accessibilityLabel("Refresh Claude service status")
                        Link(destination: URL(staticString: "https://status.claude.com")) {
                            TablerIconView(.externalLink, size: 13, color: Theme.inkSecondary, isDecorative: false)
                                .frame(width: 26, height: 26)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .tooltip("Open status.claude.com")
                        .accessibilityLabel("Open Claude status page")
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                }
            }

            if !state.components.isEmpty {
                SettingsSection(title: "Components") {
                    SettingsCard {
                        ForEach(Array(state.components.enumerated()), id: \.offset) { index, component in
                            if index > 0 { SettingsDivider() }
                            componentRow(component)
                        }
                    }
                }
            }
        }
    }

    /// Red only for a major outage, ochre for anything milder, grey while unknown.
    private func statusColor(_ status: ClaudeServiceStatus, healthy: Color) -> Color {
        switch status {
        case .operational, .none: healthy
        case .majorOutage: Theme.accent
        case .unknown: Theme.inkSecondary
        case .degradedPerformance, .partialOutage: Theme.warning
        }
    }

    /// A component in trouble gets an ochre icon; its status is spelled out in ink beside it.
    private func componentRow(_ component: (name: String, status: ClaudeServiceStatus)) -> some View {
        HStack(spacing: 8) {
            DotIconView(icon: component.status.dotIcon, size: 13, color: statusColor(component.status, healthy: Theme.inkTertiary))
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
