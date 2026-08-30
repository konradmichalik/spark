// swiftlint:disable file_length
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers
@preconcurrency import UserNotifications

// MARK: - Main Settings View

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TabView(selection: $state.selectedSettingsTab) {
            GeneralTab()
                .environmentObject(state)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            MenuBarTab()
                .environmentObject(state)
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
                .tag(SettingsTab.menuBar)

            DisplayTab()
                .environmentObject(state)
                .tabItem { Label("Display", systemImage: "square.grid.2x2") }
                .tag(SettingsTab.display)

            ConnectionTab()
                .environmentObject(state)
                .tabItem { Label("Connection", systemImage: "person.circle") }
                .tag(SettingsTab.connection)

            NotificationsTab()
                .environmentObject(state)
                .tabItem { Label("Notifications", systemImage: "bell") }
                .tag(SettingsTab.notifications)

            StatusTab()
                .environmentObject(state)
                .tabItem { Label("Status", systemImage: "heart.text.square") }
                .tag(SettingsTab.status)

            AboutTab()
                .environmentObject(state)
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 520, height: 510)
        .onAppear {
            NSApp.activate()
        }
    }
}

// MARK: - Shared Components

private struct SettingLabel: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.callout)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

private struct SettingRow<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout)
            content
        }
    }
}

// MARK: - Visual Option Card

private struct OptionCard<Preview: View>: View {
    let label: String
    let isSelected: Bool
    let preview: Preview
    let action: () -> Void

    init(
        label: String,
        isSelected: Bool,
        @ViewBuilder preview: () -> Preview,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.isSelected = isSelected
        self.preview = preview()
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preview
                    .frame(height: 36)
                    .frame(maxWidth: .infinity)
                Text(label)
                    .font(.caption2)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.2),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .foregroundColor(isSelected ? .primary : .secondary)
    }
}

// MARK: - Preview Thumbnails

private struct BarsPreviewThumb: View {
    var body: some View {
        VStack(spacing: 4) {
            BarLine(fill: 0.72, color: .green)
            BarLine(fill: 0.48, color: .green)
            BarLine(fill: 0.30, color: .green)
        }
    }
}

private struct BarLine: View {
    let fill: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.12))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: geo.size.width * fill)
            }
        }
        .frame(height: 6)
    }
}

private struct RingsConcentricThumb: View {
    var body: some View {
        ZStack {
            MiniRing(progress: 0.72, color: Color(hue: 0.35, saturation: 0.7, brightness: 0.7), lineWidth: 4, radius: 16)
            MiniRing(progress: 0.48, color: Color(hue: 0.55, saturation: 0.55, brightness: 0.75), lineWidth: 4, radius: 10.5)
        }
        .frame(width: 36, height: 36)
    }
}

private struct RingsSeparateThumb: View {
    var body: some View {
        HStack(spacing: 4) {
            MiniRing(progress: 0.72, color: Color(hue: 0.35, saturation: 0.7, brightness: 0.7), lineWidth: 3, radius: 8)
                .frame(width: 20, height: 20)
            MiniRing(progress: 0.48, color: Color(hue: 0.55, saturation: 0.55, brightness: 0.75), lineWidth: 3, radius: 8)
                .frame(width: 20, height: 20)
        }
    }
}

private struct MiniRing: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.12), lineWidth: lineWidth)
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: radius * 2, height: radius * 2)
                .rotationEffect(.degrees(-90))
        }
    }
}

private struct IconMinimalThumb: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.primary.opacity(0.6))
            .frame(width: 14, height: 3)
    }
}

private struct IconDotThumb: View {
    var body: some View {
        Circle()
            .fill(Color.primary.opacity(0.6))
            .frame(width: 8, height: 8)
    }
}

private struct IconBarThumb: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 28, height: 5)
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.primary.opacity(0.6))
                    .frame(width: 18, height: 5)
            }
        }
    }
}

private struct IconLogoThumb: View {
    var body: some View {
        ClaudeLogoShape()
            .fill(Color.primary.opacity(0.6))
            .frame(width: 18, height: 18)
    }
}

// `OptionCard` colors its preview by wrapping it in an ambient `.foregroundColor`, which the
// old SF Symbol image picked up for free. `TablerIconView` sets its own `.foregroundStyle`
// internally and does not inherit, so these previews take the selection state directly instead.
// The `arrow.up` symbol was previously drawn `.semibold`; `TablerIconView` has no weight
// parameter, so that emphasis is dropped.
private struct ValueHighestThumb: View {
    let isSelected: Bool

    var body: some View {
        TablerIconView(.arrowUp, size: 14, color: isSelected ? .primary : .secondary)
    }
}

private struct ValueSessionThumb: View {
    let isSelected: Bool

    var body: some View {
        TablerIconView(.clock, size: 14, color: isSelected ? .primary : .secondary)
    }
}

private struct ValueWeeklyThumb: View {
    let isSelected: Bool

    var body: some View {
        TablerIconView(.calendarMonth, size: 14, color: isSelected ? .primary : .secondary)
    }
}

private struct ValueNoneThumb: View {
    let isSelected: Bool

    var body: some View {
        TablerIconView(.eyeOff, size: 14, color: isSelected ? .primary : .secondary)
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @EnvironmentObject var state: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SectionHeader("Refresh", icon: .history)

                SectionCard {
                    Picker("", selection: $state.refreshMode) {
                        Text("Smart").tag("smart")
                        Text("Fixed").tag("fixed")
                    }
                    .pickerStyle(.segmented)

                    if state.refreshMode == "smart" {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Adapts refresh rate based on usage activity.")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            HStack(spacing: 8) {
                                RefreshTier(label: "Active", interval: "5m")
                                RefreshTier(label: "Idle", interval: "10m")
                                RefreshTier(label: "Idle+", interval: "15m")
                                RefreshTier(label: "Sleep", interval: "30m")
                            }
                            .font(.caption2)

                            HStack {
                                TablerIconView(.activity, size: 11, color: .green)
                                Text("Current: \(formatInterval(state.currentRefreshInterval))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Picker("Interval", selection: $state.refreshInterval) {
                            Text("5 Minutes").tag(300.0)
                            Text("10 Minutes").tag(600.0)
                            Text("30 Minutes").tag(1800.0)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: state.refreshInterval) {
                            state.startUsagePolling(interval: state.refreshInterval)
                        }
                    }
                }

                SectionHeader("Visible Sections", icon: .eye)

                SectionCard {
                    Toggle(isOn: $state.showSonnetUsage) {
                        SettingLabel(
                            title: "Sonnet Usage",
                            subtitle: "Show weekly Sonnet usage."
                        )
                    }

                    Toggle(isOn: $state.showOpusUsage) {
                        SettingLabel(
                            title: "Opus Usage",
                            subtitle: "Show weekly Opus usage."
                        )
                    }

                    Toggle(isOn: $state.showFableUsage) {
                        SettingLabel(
                            title: "Fable Usage",
                            subtitle: "Show weekly Fable usage."
                        )
                    }

                    Toggle(isOn: $state.showGraph) {
                        SettingLabel(
                            title: "Usage Graph",
                            subtitle: "Show usage history graph."
                        )
                    }

                    Toggle(isOn: $state.showProjection) {
                        SettingLabel(
                            title: "Session Projection",
                            subtitle: "Estimate whether you'll hit the limit before reset."
                        )
                    }

                    Toggle(isOn: $state.showActiveSessions) {
                        SettingLabel(
                            title: "Active Sessions",
                            subtitle: "Show sessions with activity in the last 5 minutes."
                        )
                    }

                    Toggle(isOn: $state.showStats) {
                        SettingLabel(
                            title: "Today's Stats",
                            subtitle: "Show token count, messages and sessions."
                        )
                    }

                    Toggle(isOn: $state.showProjectBreakdown) {
                        SettingLabel(
                            title: "Top Projects",
                            subtitle: "Show which projects used the most tokens."
                        )
                    }
                }

                SectionHeader("Startup", icon: .power)

                SectionCard {
                    Toggle(isOn: $launchAtLogin) {
                        SettingLabel(
                            title: "Launch at Login",
                            subtitle: "Automatically start when your Mac starts."
                        )
                    }
                    .onChange(of: launchAtLogin) {
                        do {
                            if launchAtLogin {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin.toggle()
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func formatInterval(_ seconds: TimeInterval) -> String {
        if seconds >= 60 {
            return "\(Int(seconds / 60))m"
        }
        return "\(Int(seconds))s"
    }
}

// MARK: - Refresh Tier

struct RefreshTier: View {
    let label: String
    let interval: String

    var body: some View {
        VStack(spacing: 2) {
            Text(interval)
                .fontWeight(.medium)
            Text(label)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Menu Bar Tab

struct MenuBarTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SectionHeader("Icon Style", icon: .layoutGrid)

                HStack(spacing: 8) {
                    OptionCard(
                        label: "Minimal",
                        isSelected: state.iconStyle == "minimal",
                        preview: { IconMinimalThumb() },
                        action: { state.iconStyle = "minimal" }
                    )
                    OptionCard(
                        label: "Dot",
                        isSelected: state.iconStyle == "dot",
                        preview: { IconDotThumb() },
                        action: { state.iconStyle = "dot" }
                    )
                    OptionCard(
                        label: "Bar",
                        isSelected: state.iconStyle == "bar",
                        preview: { IconBarThumb() },
                        action: { state.iconStyle = "bar" }
                    )
                    OptionCard(
                        label: "Logo",
                        isSelected: state.iconStyle == "logo",
                        preview: { IconLogoThumb() },
                        action: { state.iconStyle = "logo" }
                    )
                }

                SectionHeader("Displayed Value", icon: .numbers)

                HStack(spacing: 8) {
                    OptionCard(
                        label: "Highest",
                        isSelected: state.menuBarValue == "max",
                        preview: { ValueHighestThumb(isSelected: state.menuBarValue == "max") },
                        action: { state.menuBarValue = "max" }
                    )
                    OptionCard(
                        label: "Session",
                        isSelected: state.menuBarValue == "session",
                        preview: { ValueSessionThumb(isSelected: state.menuBarValue == "session") },
                        action: { state.menuBarValue = "session" }
                    )
                    OptionCard(
                        label: "Weekly",
                        isSelected: state.menuBarValue == "weekly",
                        preview: { ValueWeeklyThumb(isSelected: state.menuBarValue == "weekly") },
                        action: { state.menuBarValue = "weekly" }
                    )
                    OptionCard(
                        label: "None",
                        isSelected: state.menuBarValue == "none",
                        preview: { ValueNoneThumb(isSelected: state.menuBarValue == "none") },
                        action: { state.menuBarValue = "none" }
                    )
                }

                SectionHeader("Options", icon: .adjustmentsHorizontal)

                SectionCard {
                    Toggle(isOn: $state.coloredIcon) {
                        SettingLabel(
                            title: "Colored Icon",
                            subtitle: "Show icon and percentage in color based on usage level."
                        )
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Display Tab

struct DisplayTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SectionHeader("Usage Display", icon: .chartBar)

                HStack(spacing: 8) {
                    OptionCard(
                        label: "Bars",
                        isSelected: state.usageDisplayStyle == "bars",
                        preview: { BarsPreviewThumb() },
                        action: { state.usageDisplayStyle = "bars" }
                    )
                    OptionCard(
                        label: "Rings",
                        isSelected: state.usageDisplayStyle == "rings_concentric",
                        preview: { RingsConcentricThumb() },
                        action: { state.usageDisplayStyle = "rings_concentric" }
                    )
                    OptionCard(
                        label: "Side by Side",
                        isSelected: state.usageDisplayStyle == "rings_separate",
                        preview: { RingsSeparateThumb() },
                        action: { state.usageDisplayStyle = "rings_separate" }
                    )
                }

                Text("Choose how usage data is visualized in the popover.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                SectionHeader("Appearance", icon: .palette)

                SectionCard {
                    Toggle(isOn: $state.reduceTransparency) {
                        SettingLabel(
                            title: "Reduce Transparency",
                            subtitle: "Use an opaque background instead of the translucent system material."
                        )
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Connection Tab

struct ConnectionTab: View {
    @EnvironmentObject var state: AppState
    @State private var isAuthenticating = false
    @State private var authError: String?
    @State private var pastedToken: String = ""
    @State private var inputError: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SectionHeader("Authentication", icon: .key)

                if state.isAuthenticated {
                    SectionCard {
                        HStack {
                            TablerIconView(.circleCheck, size: 17, color: .green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Connected")
                                    .font(.callout)
                                    .fontWeight(.medium)
                                Text("Via \(state.authMethod.rawValue)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Log Out") { state.logout() }
                                .foregroundColor(.red)
                        }
                    }
                } else {
                    SectionCard {
                        TablerLabel("Connect to Claude Code", icon: .terminal2)
                            .font(.callout)
                            .fontWeight(.medium)

                        Text("Reads the OAuth token from the Claude Code Keychain.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if isAuthenticating {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Connecting...").font(.caption)
                            }
                        } else {
                            Button {
                                isAuthenticating = true
                                authError = nil
                                if !state.loadCredentials() {
                                    authError = "No OAuth token found in Keychain."
                                }
                                isAuthenticating = false
                            } label: {
                                HStack {
                                    TablerIconView(.key)
                                    Text("Load Credentials")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .controlSize(.large)
                        }
                    }

                    SectionCard {
                        TablerLabel("CLI not installed or not logged in?", icon: .helpCircle)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button(action: { state.openCLILogin() }, label: {
                            TablerLabel("Open Terminal & Log In", icon: .externalLink)
                        })
                        .font(.callout)
                    }
                }

                if let error = authError ?? state.lastError {
                    SectionCard {
                        TablerLabel(error, icon: .alertTriangle, tint: .orange)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                Divider()
                    .padding(.vertical, 4)

                SectionHeader("Long-lived Token", icon: .key)

                SectionCard {
                    Text("Use a long-lived token to skip macOS Keychain prompts entirely.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("In Terminal:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.top, 4)

                    Text("claude setup-token")
                        .font(.system(.caption, design: .monospaced))
                        .padding(6)
                        .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        .textSelection(.enabled)

                    Text("Paste the token below. Spark stores it in its own Keychain.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }

                SectionCard {
                    if state.authMethod == .longLivedToken {
                        HStack {
                            TablerIconView(.rosetteDiscountCheck, color: .green)
                            Text("Long-lived token is active")
                                .font(.callout)
                                .fontWeight(.medium)
                            Spacer()
                            Button("Remove") { state.clearLongLivedToken() }
                                .foregroundColor(.red)
                        }
                    } else {
                        SecureField("sk-ant-oat01-...", text: $pastedToken)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: pastedToken) { inputError = false }

                        Button {
                            if state.setLongLivedToken(pastedToken) {
                                pastedToken = ""
                            } else {
                                inputError = true
                            }
                        } label: {
                            TablerLabel("Save Token", icon: .download)
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .disabled(pastedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if inputError {
                            Text("Invalid token format (expected sk-ant-...).")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Notifications Tab

struct NotificationsTab: View {
    @EnvironmentObject var state: AppState
    @State private var testSent = false
    @State private var permissionStatus: String = "Checking..."
    @State private var permissionDenied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SectionHeader("Notifications", icon: .bellRinging)

                SectionCard {
                    Toggle(isOn: $state.notificationsEnabled) {
                        SettingLabel(
                            title: "Enable Notifications",
                            subtitle: "Get notified about high usage and status changes."
                        )
                    }

                    HStack {
                        TablerIconView(
                            permissionDenied ? .alertTriangle : .circleCheck,
                            size: 11,
                            color: permissionDenied ? .orange : .green
                        )
                        Text("System: \(permissionStatus)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if permissionDenied {
                            Button("Open Settings") {
                                if let url = URL(
                                    string: "x-apple.systempreferences:com.apple.preference.notifications"
                                ) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
                .onAppear { checkPermission() }
                .onChange(of: state.notificationsEnabled) {
                    if state.notificationsEnabled { requestAndCheck() }
                }

                SectionHeader("Thresholds", icon: .chartBar)

                SectionCard {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Warning")
                                .font(.callout)
                            Spacer()
                            Text("\(Int(state.warningThreshold))%")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundColor(.orange)
                        }
                        Slider(value: $state.warningThreshold, in: 50...90, step: 5)
                            .tint(.orange)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Critical")
                                .font(.callout)
                            Spacer()
                            Text("\(Int(state.criticalThreshold))%")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundColor(.red)
                        }
                        Slider(value: $state.criticalThreshold, in: 75...100, step: 5)
                            .tint(.red)
                    }

                    if state.criticalThreshold <= state.warningThreshold {
                        TablerLabel("Critical must be higher than Warning.", icon: .alertTriangle, tint: .orange)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .opacity(state.notificationsEnabled ? 1 : 0.5)
                .disabled(!state.notificationsEnabled)

                SectionHeader("Events", icon: .bellBolt)

                SectionCard {
                    Toggle(isOn: $state.notifyOnReset) {
                        Text("Notify on usage reset")
                            .font(.callout)
                    }

                    Toggle(isOn: $state.notifyOnStatusChange) {
                        Text("Notify on status incidents")
                            .font(.callout)
                    }

                    Toggle(isOn: $state.notifyOnNewVersion) {
                        Text("Notify on new app version")
                            .font(.callout)
                    }

                    Toggle(isOn: $state.notifyOnCLIUpdate) {
                        Text("Notify on new Claude Code version")
                            .font(.callout)
                    }

                    SettingRow(title: "Check Interval") {
                        Picker("", selection: $state.updateCheckInterval) {
                            Text("1h").tag(3600.0)
                            Text("3h").tag(10800.0)
                            Text("6h").tag(21600.0)
                            Text("12h").tag(43200.0)
                            Text("24h").tag(86400.0)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: state.updateCheckInterval) {
                            state.restartUpdateCheckPolling()
                        }
                    }
                }
                .opacity(state.notificationsEnabled ? 1 : 0.5)
                .disabled(!state.notificationsEnabled)

                SectionCard {
                    HStack {
                        Button(action: sendTestNotification) {
                            TablerLabel("Send Test Notification", icon: .send)
                        }
                        .disabled(!state.notificationsEnabled)

                        if testSent {
                            TablerLabel("Sent", icon: .circleCheck, tint: .green)
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
                .opacity(state.notificationsEnabled ? 1 : 0.5)
                .disabled(!state.notificationsEnabled)
            }
            .padding()
        }
    }

    private func checkPermission() {
        Task {
            let status = await UNUserNotificationCenter.current()
                .notificationSettings().authorizationStatus
            switch status {
            case .authorized:
                permissionStatus = "Allowed"
                permissionDenied = false
            case .denied:
                permissionStatus = "Denied"
                permissionDenied = true
            case .notDetermined:
                permissionStatus = "Not requested yet"
                permissionDenied = false
            case .provisional:
                permissionStatus = "Provisional"
                permissionDenied = false
            case .ephemeral:
                permissionStatus = "Ephemeral"
                permissionDenied = false
            @unknown default:
                permissionStatus = "Unknown"
                permissionDenied = false
            }
        }
    }

    private func requestAndCheck() {
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            checkPermission()
        }
    }

    private func sendTestNotification() {
        Task {
            let granted = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            checkPermission()
            guard granted == true else { return }

            let content = UNMutableNotificationContent()
            content.title = "Spark"
            content.body = "Test notification successful!"
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(
                identifier: "test-\(UUID())",
                content: content,
                trigger: trigger
            )
            try? await UNUserNotificationCenter.current().add(request)
        }

        testSent = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            testSent = false
        }
    }
}

// MARK: - Status Tab

struct StatusTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SectionHeader("Claude Services", icon: .heart)

                Text("Live status powered by the Anthropic status page. The popover only shows a warning during active incidents.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                SectionCard {
                    HStack {
                        TablerIconView(state.status.icon, size: 15, color: .primary)
                        Text(state.statusDescription)
                            .fontWeight(.medium)
                        Spacer()
                        Button {
                            Task { await state.fetchStatus() }
                        } label: {
                            TablerIconView(.refresh, size: 11)
                        }
                        .buttonStyle(.borderless)

                        Link(destination: URL(string: "https://status.claude.com")!) {
                            TablerIconView(.externalLink, size: 11)
                        }
                        .buttonStyle(.borderless)
                        .help("Open status.claude.com")
                    }
                }

                if !state.components.isEmpty {
                    SectionHeader("Components", icon: .server)

                    SectionCard {
                        ForEach(
                            Array(state.components.enumerated()),
                            id: \.offset
                        ) { _, component in
                            HStack {
                                TablerIconView(
                                    component.status.icon,
                                    size: 12,
                                    color: component.status.isHealthy ? .green : Theme.sparkOrange
                                )
                                Text(component.name)
                                    .font(.callout)
                                Spacer()
                                Text(component.status.displayName)
                                    .font(.callout)
                                    .foregroundColor(
                                        component.status.isHealthy ? .secondary : Theme.sparkOrange
                                    )
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - About Tab

struct AboutTab: View {
    @EnvironmentObject var state: AppState
    @State private var updateState: UpdateCheckState = .idle
    @State private var showClearRollupsConfirmation = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            SparkLogoView(size: 80)

            Text("Spark")
                .font(.custom("InstrumentSerif-Regular", size: 28))

            Text("Version \(appVersion)")
                .font(.caption)
                .foregroundColor(.secondary)

            if let local = state.localCLIVersion {
                let isOutdated = state.latestCLIVersion.map { CLIVersionClient.isNewer($0, than: local) } ?? false

                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text("Claude Code \(local) \u{00B7} via \(state.claudeCodeInstallMethod.displayLabel)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if isOutdated, let latest = state.latestCLIVersion {
                            Text("\u{2192} \(latest)")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    if isOutdated {
                        Text(state.claudeCodeInstallMethod.updateCommand)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Text("Claude Code usage in your menu bar.")
                .font(.callout)
                .foregroundColor(.secondary)

            if let configDir = ClaudeConfigDirectory.resolveCurrent().primary {
                Text("Config directory: \(configDir.path)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                Button {
                    if let url = URL(string: "https://konradmichalik.github.io/spark/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    TablerLabel("Website", icon: .world)
                }
                .buttonStyle(.bordered)

                Button {
                    if let url = URL(string: "https://github.com/konradmichalik/spark") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    TablerLabel("GitHub", icon: .link)
                }
                .buttonStyle(.bordered)
            }

            updateCheckSection

            rollupDataSection

            Spacer()

            Text("\u{00A9} 2026 Konrad Michalik")
                .font(.caption2)
                .foregroundColor(.secondary)

            Link("Icons by Tabler Icons (MIT)", destination: URL(string: "https://tabler.io/icons")!)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var rollupDataSection: some View {
        HStack(spacing: 8) {
            Button("Export Rollups\u{2026}") {
                exportRollups()
            }
            .buttonStyle(.bordered)
            .disabled(state.rollups.isEmpty)

            Button("Clear Rollups") {
                showClearRollupsConfirmation = true
            }
            .buttonStyle(.bordered)
            .disabled(state.rollups.isEmpty)
        }
        .confirmationDialog(
            "Clear all rollup data?",
            isPresented: $showClearRollupsConfirmation
        ) {
            Button("Clear Rollups", role: .destructive) {
                state.clearRollups()
            }
        } message: {
            Text("This permanently deletes daily token totals recorded beyond the transcript retention window. This cannot be undone.")
        }
    }

    private func exportRollups() {
        guard let data = state.exportRollupsJSON() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "spark-rollups.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }

    @ViewBuilder
    private var updateCheckSection: some View {
        switch updateState {
        case .idle:
            Button("Check for Updates") {
                Task { await checkForUpdates() }
            }
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .upToDate:
            TablerLabel("You're up to date", icon: .circleCheck, tint: .green)
                .foregroundStyle(.green)
        case .available(let version, let url):
            VStack(spacing: 6) {
                TablerLabel("Version \(version) available", icon: .circleArrowUp, tint: .orange)
                    .foregroundStyle(.orange)
                Link("Download", destination: url)
            }
        case .error(let message):
            TablerLabel(message, icon: .alertTriangle, tint: .red)
                .foregroundStyle(.red)
        }
    }

    private func checkForUpdates() async {
        updateState = .checking

        guard let url = URL(
            string: "https://api.github.com/repos/konradmichalik/spark/releases/latest"
        ) else {
            updateState = .error("Invalid URL")
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latestVersion = release.tagName.trimmingCharacters(
                in: CharacterSet(charactersIn: "v")
            )

            if latestVersion == appVersion {
                updateState = .upToDate
            } else if let releaseURL = URL(string: release.htmlUrl) {
                updateState = .available(version: latestVersion, url: releaseURL)
            } else {
                updateState = .error("Could not parse release URL")
            }
        } catch {
            updateState = .error("Could not check for updates")
        }
    }
}

private enum UpdateCheckState {
    case idle
    case checking
    case upToDate
    case available(version: String, url: URL)
    case error(String)
}

struct GitHubRelease: Decodable {
    let tagName: String
    let htmlUrl: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
    }
}
