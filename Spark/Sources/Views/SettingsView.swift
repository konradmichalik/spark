// swiftlint:disable file_length
import SwiftUI
import ServiceManagement
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

struct CardView<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

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

private struct ValueHighestThumb: View {
    var body: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: 14, weight: .semibold))
    }
}

private struct ValueSessionThumb: View {
    var body: some View {
        Image(systemName: "clock")
            .font(.system(size: 14))
    }
}

private struct ValueWeeklyThumb: View {
    var body: some View {
        Image(systemName: "calendar")
            .font(.system(size: 14))
    }
}

private struct ValueNoneThumb: View {
    var body: some View {
        Image(systemName: "eye.slash")
            .font(.system(size: 14))
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @EnvironmentObject var state: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SectionHeader(title: "Refresh", icon: "clock.arrow.circlepath")

                CardView {
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
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(.green)
                                    .font(.caption2)
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

                SectionHeader(title: "Visible Sections", icon: "eye")

                CardView {
                    Toggle(isOn: $state.showSonnetUsage) {
                        SettingLabel(
                            title: "Sonnet Usage",
                            subtitle: "Show weekly Sonnet usage."
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

                    Toggle(isOn: $state.showStats) {
                        SettingLabel(
                            title: "Today's Stats",
                            subtitle: "Show token count, messages and sessions."
                        )
                    }
                }

                SectionHeader(title: "Startup", icon: "power")

                CardView {
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
                SectionHeader(title: "Icon Style", icon: "square.grid.4x3.fill")

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

                SectionHeader(title: "Displayed Value", icon: "textformat.123")

                HStack(spacing: 8) {
                    OptionCard(
                        label: "Highest",
                        isSelected: state.menuBarValue == "max",
                        preview: { ValueHighestThumb() },
                        action: { state.menuBarValue = "max" }
                    )
                    OptionCard(
                        label: "Session",
                        isSelected: state.menuBarValue == "session",
                        preview: { ValueSessionThumb() },
                        action: { state.menuBarValue = "session" }
                    )
                    OptionCard(
                        label: "Weekly",
                        isSelected: state.menuBarValue == "weekly",
                        preview: { ValueWeeklyThumb() },
                        action: { state.menuBarValue = "weekly" }
                    )
                    OptionCard(
                        label: "None",
                        isSelected: state.menuBarValue == "none",
                        preview: { ValueNoneThumb() },
                        action: { state.menuBarValue = "none" }
                    )
                }

                SectionHeader(title: "Options", icon: "slider.horizontal.3")

                CardView {
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
                SectionHeader(title: "Usage Display", icon: "chart.bar.fill")

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

                SectionHeader(title: "Appearance", icon: "paintbrush")

                CardView {
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

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SectionHeader(title: "Authentication", icon: "key.fill")

                if state.isAuthenticated {
                    CardView {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title2)
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
                    CardView {
                        Label("Connect to Claude Code", systemImage: "terminal.fill")
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
                                    Image(systemName: "key.fill")
                                    Text("Load Credentials")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .controlSize(.large)
                        }
                    }

                    CardView {
                        Label("CLI not installed or not logged in?", systemImage: "questionmark.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button(action: { state.openCLILogin() }, label: {
                            Label("Open Terminal & Log In", systemImage: "arrow.up.forward.app.fill")
                        })
                        .font(.callout)
                    }
                }

                if let error = authError ?? state.lastError {
                    CardView {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
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
                SectionHeader(title: "Notifications", icon: "bell.badge")

                CardView {
                    Toggle(isOn: $state.notificationsEnabled) {
                        SettingLabel(
                            title: "Enable Notifications",
                            subtitle: "Get notified about high usage and status changes."
                        )
                    }

                    HStack {
                        Image(systemName: permissionDenied
                            ? "exclamationmark.triangle.fill"
                            : "checkmark.circle.fill"
                        )
                            .foregroundColor(permissionDenied ? .orange : .green)
                            .font(.caption)
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

                SectionHeader(title: "Thresholds", icon: "chart.bar.fill")

                CardView {
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
                        Label(
                            "Critical must be higher than Warning.",
                            systemImage: "exclamationmark.triangle"
                        )
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .opacity(state.notificationsEnabled ? 1 : 0.5)
                .disabled(!state.notificationsEnabled)

                SectionHeader(title: "Events", icon: "bell.and.waves.left.and.right")

                CardView {
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
                }
                .opacity(state.notificationsEnabled ? 1 : 0.5)
                .disabled(!state.notificationsEnabled)

                CardView {
                    HStack {
                        Button(action: sendTestNotification) {
                            Label("Send Test Notification", systemImage: "paperplane")
                        }
                        .disabled(!state.notificationsEnabled)

                        if testSent {
                            Label("Sent", systemImage: "checkmark.circle.fill")
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
                SectionHeader(title: "Claude Services", icon: "heart.text.square")

                Text("Live status powered by the Anthropic status page. The popover only shows a warning during active incidents.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                CardView {
                    HStack {
                        Image(systemName: state.status.emoji)
                            .font(.title3)
                        Text(state.statusDescription)
                            .fontWeight(.medium)
                        Spacer()
                        Button {
                            Task { await state.fetchStatus() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)

                        // swiftlint:disable:next force_unwrapping
                        Link(destination: URL(string: "https://status.claude.com")!) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .help("Open status.claude.com")
                    }
                }

                if !state.components.isEmpty {
                    SectionHeader(title: "Components", icon: "server.rack")

                    CardView {
                        ForEach(
                            Array(state.components.enumerated()),
                            id: \.offset
                        ) { _, component in
                            HStack {
                                Image(systemName: component.status.emoji)
                                    .foregroundColor(
                                        component.status.isHealthy ? .green : Theme.sparkOrange
                                    )
                                    .font(.caption)
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
    @State private var updateState: UpdateCheckState = .idle

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

            Text("Claude Code usage in your menu bar.")
                .font(.callout)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Button {
                    if let url = URL(string: "https://konradmichalik.github.io/spark/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Website", systemImage: "globe")
                }
                .buttonStyle(.bordered)

                Button {
                    if let url = URL(string: "https://github.com/konradmichalik/spark") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("GitHub", systemImage: "link")
                }
                .buttonStyle(.bordered)
            }

            updateCheckSection

            Spacer()

            Text("\u{00A9} 2026 Konrad Michalik")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
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
            Label("You're up to date", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .available(let version, let url):
            VStack(spacing: 6) {
                Label("Version \(version) available", systemImage: "arrow.up.circle.fill")
                    .foregroundStyle(.orange)
                Link("Download", destination: url)
            }
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
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
