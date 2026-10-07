import SwiftUI

/// Codex part of Settings > Connection. There is nothing to sign in to here: Spark only reads
/// the sign-in the Codex CLI already wrote, so this section shows whether it found one.
struct CodexConnectionSection: View {
    @EnvironmentObject var codex: CodexState

    var body: some View {
        SectionHeader("Codex", icon: .terminal2)

        SectionCard {
            Toggle(isOn: $codex.isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show Codex Usage")
                        .font(.callout)
                    Text("Reads the ChatGPT sign-in of the Codex CLI. Spark never refreshes or changes it.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .onChange(of: codex.isEnabled) { codex.applySettingsChange() }
        }

        if codex.isEnabled {
            SectionCard {
                if codex.isAvailable {
                    signedIn
                } else {
                    notFound
                }
            }
        }
    }

    private var signedIn: some View {
        HStack {
            if codex.needsSignIn {
                TablerIconView(.refreshAlert, size: 17, color: .orange)
            } else {
                TablerIconView(.circleCheck, size: 17, color: .green)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(codex.needsSignIn ? "Sign-in expired" : "Connected")
                    .font(.callout)
                    .fontWeight(.medium)
                Text(codex.usage?.planDisplayName.map { "ChatGPT \($0)" } ?? "ChatGPT")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var notFound: some View {
        TablerLabel("No ChatGPT sign-in found", icon: .helpCircle)
            .font(.callout)
            .fontWeight(.medium)

        Text("Spark looks for \(CodexHome.authFile.path). Sign in with the Codex CLI, then check again:")
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        Text("codex login")
            .font(.system(.caption, design: .monospaced))
            .padding(6)
            .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .textSelection(.enabled)

        Text("Credentials stored in the Keychain (cli_auth_credentials_store = keyring) are not supported yet.")
            .font(.caption2)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        Button("Check Again") { codex.applySettingsChange() }
    }
}
