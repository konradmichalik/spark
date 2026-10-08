import SwiftUI

/// The Codex card in Settings > Connections. There is nothing to sign in to here: Spark only
/// reads the sign-in the Codex CLI already wrote, so the card says whether it found one.
struct CodexConnectionCard: View {
    @EnvironmentObject var codex: CodexState

    private var line: ConnectionLine {
        ConnectionSummary.codex(
            isEnabled: codex.isEnabled, isAvailable: codex.isAvailable, needsSignIn: codex.needsSignIn,
            plan: codex.usage?.planDisplayName
        )
    }

    var body: some View {
        SettingsCard {
            ConnectionHeader(name: "Codex", line: line) {
                TablerIconView(.brandOpenai, size: 22, color: Theme.ink)
            } trailing: {
                HStack(spacing: 10) {
                    if line.state == .expired || line.state == .notFound {
                        Button("Check again") { codex.applySettingsChange() }
                            .buttonStyle(.paper)
                    }
                    Toggle("Show Codex", isOn: $codex.isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(Theme.ink)
                }
            }
            if line.state == .expired || line.state == .notFound {
                SettingsDivider()
                signInHelp
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            } else if line.state == .off {
                SettingsDivider()
                SettingsNote(text: "Reads the ChatGPT sign-in of the Codex CLI. Spark never refreshes or changes it.")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .onChange(of: codex.isEnabled) { codex.applySettingsChange() }
    }

    private var signInHelp: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Run")
                CommandText("codex login")
                Text("in Terminal, then check again.")
            }
            HStack(spacing: 4) {
                Text("Spark only reads")
                CommandText(CodexHome.authFile.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                Text("and never renews the sign-in.")
            }
            if line.state == .notFound {
                Text("Sign-ins kept in the keychain (cli_auth_credentials_store = keyring) are not supported yet.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.inkSecondary)
    }
}
