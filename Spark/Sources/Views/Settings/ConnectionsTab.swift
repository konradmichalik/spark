import SwiftUI

/// One card per provider (board 10b), and a placeholder for the providers still to come.
struct ConnectionsTab: View {
    var body: some View {
        SettingsPage {
            ClaudeConnectionCard()
            CodexConnectionCard()
            FutureProviderCard()
        }
    }
}

/// The head of a provider card: logo, name, status line, one action and an optional switch.
struct ConnectionHeader<Logo: View, Trailing: View>: View {
    let name: String
    let line: ConnectionLine
    @ViewBuilder var logo: () -> Logo
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            logo()
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 6) {
                    ConnectionDot(state: line.state)
                    Text(line.text)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct ClaudeConnectionCard: View {
    @EnvironmentObject var state: AppState
    @State private var authError: String?
    @State private var showsToken = false

    private var line: ConnectionLine {
        ConnectionSummary.claude(
            isAuthenticated: state.isAuthenticated, needsReconnect: state.needsReconnect,
            plan: state.isAuthenticated ? state.accountTier.displayName : nil, method: state.authMethod
        )
    }

    var body: some View {
        SettingsCard {
            ConnectionHeader(name: "Claude Code", line: line) {
                ClaudeLogoShape().fill(Theme.claudeLogo)
            } trailing: {
                action
            }
            if let error = authError ?? state.lastError {
                SettingsDivider()
                notice(error)
            }
            if !state.isAuthenticated {
                SettingsDivider()
                SettingsRow(title: "Claude Code not installed or not signed in?") {
                    Button("Open Terminal") { state.openCLILogin() }
                        .buttonStyle(.paper)
                }
            }
            SettingsDivider()
            tokenDisclosure
            if showsToken {
                LongLivedTokenForm()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private var action: some View {
        switch line.state {
        case .connected:
            Button("Log out") { state.logout() }
                .buttonStyle(.paper)
        case .expired:
            Button("Reconnect") { state.reconnect() }
                .buttonStyle(.paperPrimary)
        case .notFound, .off:
            Button("Load from keychain") {
                authError = state.loadCredentials() ? nil : "No Claude Code sign-in found in the keychain."
            }
            .buttonStyle(.paperPrimary)
        }
    }

    private func notice(_ text: String) -> some View {
        HStack(spacing: 8) {
            TablerIconView(.alertTriangle, size: 13, color: Theme.warning)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var tokenDisclosure: some View {
        Button {
            showsToken.toggle()
        } label: {
            HStack(spacing: 8) {
                Text("Long-lived token instead of the keychain")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(state.authMethod == .longLivedToken ? "On" : "Off")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSecondary)
                TablerIconView(.chevronRight, size: 12, color: Theme.inkTertiary)
                    .rotationEffect(.degrees(showsToken ? -90 : 90))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(state.authMethod == .longLivedToken ? "On" : "Off")
        .accessibilityHint(showsToken ? "Hides the token settings" : "Shows the token settings")
    }
}

/// The long-lived token: how to get one, the field to paste it into, or the active token.
private struct LongLivedTokenForm: View {
    @EnvironmentObject var state: AppState
    @State private var pastedToken = ""
    @State private var inputError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.authMethod == .longLivedToken {
                HStack {
                    Text("Spark uses your long-lived token and never asks the keychain of Claude Code.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Remove") { state.clearLongLivedToken() }
                        .buttonStyle(.paper)
                }
            } else {
                HStack(spacing: 4) {
                    Text("Skips keychain prompts. Run")
                    CommandText("claude setup-token")
                    Text("and paste the token.")
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSecondary)
                HStack(spacing: 8) {
                    SecureField("sk-ant-oat01-…", text: $pastedToken)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .onChange(of: pastedToken) { inputError = false }
                    Button("Save") { save() }
                        .buttonStyle(.paperPrimary)
                        .disabled(pastedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if inputError {
                    TablerLabel("This is not a token (expected sk-ant-…).", icon: .alertTriangle, size: 12, tint: Theme.warning)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.ink)
                }
                SettingsNote(text: "Spark keeps the token in its own keychain item.")
            }
        }
    }

    private func save() {
        if state.setLongLivedToken(pastedToken) {
            pastedToken = ""
        } else {
            inputError = true
        }
    }
}

/// Stands for the providers still to come: dashed, no action.
private struct FutureProviderCard: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Theme.inkTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("More providers")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                Text("Each provider Spark learns gets its own card here.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
        }
        .padding(14)
        .overlay(shape.strokeBorder(Theme.inkTertiary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .accessibilityElement(children: .combine)
    }
}
