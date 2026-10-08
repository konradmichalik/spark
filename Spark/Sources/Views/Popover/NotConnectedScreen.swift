import AppKit
import SwiftUI

/// Claude when Spark has no sign-in (board 9): an empty dot ring with a link icon, one
/// sentence, loading the sign-in from the keychain as the primary action and the long-lived
/// token in Settings as the secondary one. Other providers stay usable in their tabs.
struct NotConnectedScreen: View {
    @EnvironmentObject var state: AppState

    @State private var loadFailed = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                DotRing(value: 0, count: 40, gap: 0, dotSize: 4.5)
                TablerIconView(.link, size: 24, color: Theme.inkSecondary)
            }
            .frame(width: 120, height: 120)
            .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("Claude Code is not connected")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(loadFailed
                    ? "No Claude Code sign-in found in the keychain. Sign in with claude, then try again."
                    : "Spark reads the sign-in that Claude Code stores in the keychain.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                loadFailed = !state.loadCredentials()
            } label: {
                Text("Load from keychain")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.paper)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 32)
                    .background(Theme.ink, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            SettingsLink {
                Text("Use a long-lived token")
                    .font(.system(size: 12))
                    .underline()
                    .foregroundStyle(Theme.ink)
                    .frame(minHeight: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the connection settings")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        // The secondary action opens Settings, which then starts on the connection tab.
        .onAppear { state.selectedSettingsTab = .connection }
    }
}

/// The footer under the not-connected screen: what keeps working, and quit.
struct NotConnectedFooter: View {
    let codexIsActive: Bool

    var body: some View {
        HStack {
            if codexIsActive {
                Text("Codex keeps running")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                TablerIconView(.power, size: 14, color: Theme.inkSecondary, isDecorative: false)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .tooltip("Quit")
            .accessibilityLabel("Quit Spark")
        }
    }
}
