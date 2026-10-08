import SwiftUI

/// A card row that opens more settings below it: title, a short state on the right, a chevron.
struct CardDisclosure: View {
    let title: String
    let value: String
    @Binding var isOpen: Bool
    let openHint: String
    let closedHint: String

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(value)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSecondary)
                TablerIconView(.chevronRight, size: 12, color: Theme.inkTertiary)
                    .rotationEffect(.degrees(isOpen ? -90 : 90))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(value)
        .accessibilityHint(isOpen ? openHint : closedHint)
    }
}

/// One line of a provider card: what it is and the value, selectable so a path can be copied.
struct ProviderFactRow: View {
    let title: String
    let value: String

    var body: some View {
        SettingsRow(title: title) {
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

/// Claude Code's installed version, how it was installed, an update hint and where its data lives.
struct ClaudeCLIFacts: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if let local = state.localCLIVersion {
            let latest = state.latestCLIVersion.flatMap { CLIVersionClient.isNewer($0, than: local) ? $0 : nil }
            SettingsDivider()
            ProviderFactRow(
                title: "Version",
                value: "\(local) \u{00B7} via \(state.claudeCodeInstallMethod.displayLabel)"
                    + (latest.map { " \u{2192} \($0) available" } ?? "")
            )
            if latest != nil {
                CommandText(state.claudeCodeInstallMethod.updateCommand)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
        if let directory = ClaudeConfigDirectory.resolveCurrent().primary {
            SettingsDivider()
            ProviderFactRow(title: "Data", value: directory.path)
        }
    }
}

/// The Sonnet, Opus and Fable weeks that show under More limits in the popover.
struct ClaudeModelLimitToggles: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            SettingsToggle(title: "Sonnet", subtitle: "Weekly Sonnet limit.", isOn: $state.showSonnetUsage)
            SettingsDivider()
            SettingsToggle(title: "Opus", subtitle: "Weekly Opus limit.", isOn: $state.showOpusUsage)
            SettingsDivider()
            SettingsToggle(title: "Fable", subtitle: "Weekly Fable limit.", isOn: $state.showFableUsage)
        }
    }

    static func summary(_ state: AppState) -> String {
        let on = [state.showSonnetUsage, state.showOpusUsage, state.showFableUsage].filter { $0 }.count
        return on == 0 ? "Off" : "\(on) of 3"
    }
}

/// The Codex CLI's installed version and where its data lives.
struct CodexCLIFacts: View {
    @State private var version: String?

    var body: some View {
        VStack(spacing: 0) {
            if let version {
                SettingsDivider()
                ProviderFactRow(title: "Version", value: version)
            }
            SettingsDivider()
            ProviderFactRow(title: "Data", value: CodexHome.current.path)
        }
        .task { version = await CLIVersionClient.readLocalVersion(command: "codex") }
    }
}
