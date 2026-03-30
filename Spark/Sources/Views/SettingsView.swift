import SwiftUI
import ServiceManagement
import UserNotifications

// MARK: - Main Settings View

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TabView {
            GeneralTab()
                .environmentObject(state)
                .tabItem { Label("General", systemImage: "gearshape") }

            AppearanceTab()
                .environmentObject(state)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            ConnectionTab()
                .environmentObject(state)
                .tabItem { Label("Connection", systemImage: "person.circle") }

            NotificationsTab()
                .environmentObject(state)
                .tabItem { Label("Notifications", systemImage: "bell") }

            StatusTab()
                .environmentObject(state)
                .tabItem { Label("Status", systemImage: "heart.text.square") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 440)
    }
}

// MARK: - Card Style

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

// MARK: - Connection Tab

struct ConnectionTab: View {
    @EnvironmentObject var state: AppState
    @State private var isAuthenticating = false
    @State private var authError: String?

    var body: some View {
        VStack(spacing: 12) {
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
                        Button(action: {
                            isAuthenticating = true
                            authError = nil
                            if !state.loadCredentials() {
                                authError = "No OAuth token found in Keychain."
                            }
                            isAuthenticating = false
                        }) {
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

                    Button(action: { state.openCLILogin() }) {
                        Label("Open Terminal & Log In", systemImage: "arrow.up.forward.app.fill")
                    }
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

            Spacer()
        }
        .padding()
    }
}

// MARK: - Appearance Tab

struct AppearanceTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                CardView {
                    Label("Menu Bar", systemImage: "menubar.rectangle")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    SettingRow(title: "Icon Style") {
                        Picker("", selection: $state.iconStyle) {
                            Text("Minimal").tag("minimal")
                            Text("Dot").tag("dot")
                            Text("Logo").tag("logo")
                        }
                        .pickerStyle(.segmented)
                    }

                    SettingRow(title: "Displayed Value") {
                        Picker("", selection: $state.menuBarValue) {
                            Text("Highest").tag("max")
                            Text("Session").tag("session")
                            Text("Weekly").tag("weekly")
                        }
                        .pickerStyle(.segmented)
                    }

                    Toggle(isOn: $state.coloredIcon) {
                        SettingLabel(
                            title: "Colored Icon",
                            subtitle: "Show icon and percentage in color based on usage level."
                        )
                    }
                }

                CardView {
                    Label("Popover", systemImage: "list.bullet")
                        .font(.caption)
                        .foregroundColor(.secondary)

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
            }
            .padding()
        }
    }
}

// MARK: - Setting Helpers

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

// MARK: - General Tab

struct GeneralTab: View {
    @EnvironmentObject var state: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 12) {
            CardView {
                Label("Refresh Mode", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("", selection: $state.refreshMode) {
                    Text("Smart").tag("smart")
                    Text("Fixed").tag("fixed")
                }
                .pickerStyle(.segmented)

                if state.refreshMode == "smart" {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Automatically adjusts refresh rate based on usage activity.")
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

            CardView {
                Toggle(isOn: $launchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                            .font(.callout)
                        Text("Automatically start when your Mac starts.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
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

            Spacer()
        }
        .padding()
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

// MARK: - Notifications Tab

struct NotificationsTab: View {
    @EnvironmentObject var state: AppState
    @State private var testSent = false
    @State private var permissionStatus: String = "Checking..."
    @State private var permissionDenied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                CardView {
                    Toggle(isOn: $state.notificationsEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Notifications")
                                .font(.callout)
                            Text("Get notified about high usage and status changes.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Image(systemName: permissionDenied ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundColor(permissionDenied ? .orange : .green)
                            .font(.caption)
                        Text("System: \(permissionStatus)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if permissionDenied {
                            Button("Open Settings") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
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

                CardView {
                    Label("Thresholds", systemImage: "chart.bar.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)

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
                        Label("Critical must be higher than Warning.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .opacity(state.notificationsEnabled ? 1 : 0.5)
                .disabled(!state.notificationsEnabled)

                CardView {
                    Label("Events", systemImage: "bell.badge")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle(isOn: $state.notifyOnReset) {
                        Text("Notify on usage reset")
                            .font(.callout)
                    }

                    Toggle(isOn: $state.notifyOnStatusChange) {
                        Text("Notify on status incidents")
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
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
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
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            checkPermission()
        }
    }

    private func sendTestNotification() {
        Task {
            let granted = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            checkPermission()
            guard granted == true else { return }

            let content = UNMutableNotificationContent()
            content.title = "Spark"
            content.body = "Test notification successful!"
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: "test-\(UUID())", content: content, trigger: trigger)
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
            VStack(spacing: 12) {
                Text("Live status of Claude services powered by the Anthropic status page. The main popover only shows a warning when there is an active incident.")
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
                        Button(action: {
                            Task { await state.fetchStatus() }
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)

                        Link(destination: URL(string: "https://status.anthropic.com")!) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .help("Open status.anthropic.com")
                    }
                }

                if !state.components.isEmpty {
                    CardView {
                        Label("Components", systemImage: "server.rack")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ForEach(Array(state.components.enumerated()), id: \.offset) { _, component in
                            HStack {
                                Image(systemName: component.status.emoji)
                                    .foregroundColor(component.status.isHealthy ? .green : .orange)
                                    .font(.caption)
                                Text(component.name)
                                    .font(.callout)
                                Spacer()
                                Text(component.status.displayName)
                                    .font(.callout)
                                    .foregroundColor(component.status.isHealthy ? .secondary : .orange)
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
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image("SparkLogo")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)

            Text("Spark")
                .font(.system(size: 22, weight: .semibold))

            Text("Version \(appVersion)")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Claude Code usage in your menu bar.")
                .font(.callout)
                .foregroundColor(.secondary)

            Button {
                if let url = URL(string: "https://github.com/konradmichalik/spark") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("GitHub Repository", systemImage: "link")
            }
            .buttonStyle(.bordered)

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

        guard let url = URL(string: "https://api.github.com/repos/konradmichalik/spark/releases/latest") else {
            updateState = .error("Invalid URL")
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))

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

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlUrl: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
    }
}
