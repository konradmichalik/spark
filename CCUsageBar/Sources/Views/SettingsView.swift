import SwiftUI
import ServiceManagement
import UserNotifications

// MARK: - Main Settings View

struct SettingsView: View {
    @EnvironmentObject var usageService: UsageService
    @EnvironmentObject var statusService: StatusService

    var body: some View {
        TabView {
            ConnectionTab()
                .environmentObject(usageService)
                .tabItem { Label("Connection", systemImage: "person.circle") }

            AppearanceTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            GeneralTab()
                .environmentObject(usageService)
                .tabItem { Label("General", systemImage: "gearshape") }

            NotificationsTab()
                .tabItem { Label("Notifications", systemImage: "bell") }

            StatusTab()
                .environmentObject(statusService)
                .tabItem { Label("Status", systemImage: "heart.text.square") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 380)
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
    @EnvironmentObject var usageService: UsageService
    @StateObject private var oauthService = OAuthService()

    var body: some View {
        VStack(spacing: 12) {
            if usageService.isAuthenticated {
                CardView {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connected")
                                .font(.callout)
                                .fontWeight(.medium)
                            Text("Via \(usageService.authMethod.rawValue)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Log Out") { usageService.logout() }
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

                    if oauthService.isAuthenticating {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Connecting...").font(.caption)
                        }
                    } else {
                        Button(action: {
                            oauthService.onAuthenticated = { token in
                                usageService.setAuthenticated(token: token)
                            }
                            oauthService.loginViaCLI()
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

                    Button(action: { oauthService.openCLILogin() }) {
                        Label("Open Terminal & Log In", systemImage: "arrow.up.forward.app.fill")
                    }
                    .font(.callout)
                }
            }

            if let error = oauthService.error ?? usageService.error {
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
    @AppStorage("iconStyle") private var iconStyle: String = "logo"
    @AppStorage("menuBarValue") private var menuBarValue: String = "max"
    @AppStorage("showSonnetUsage") private var showSonnetUsage: Bool = true

    var body: some View {
        VStack(spacing: 12) {
            // Icon Style
            CardView {
                Label("Menu Bar Icon", systemImage: "menubar.rectangle")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("", selection: $iconStyle) {
                    Text("Minimal (42%)").tag("minimal")
                    Text("Dot + 42%").tag("dot")
                    Text("Logo + 42%").tag("logo")
                }
                .pickerStyle(.segmented)
            }

            // Displayed Value
            CardView {
                Label("Displayed Value", systemImage: "number")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("", selection: $menuBarValue) {
                    Text("Highest").tag("max")
                    Text("Session (5h)").tag("session")
                    Text("Weekly (7d)").tag("weekly")
                }
                .pickerStyle(.segmented)

                Text("Choose which usage value is shown as percentage in the menu bar.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Popover Options
            CardView {
                Label("Popover", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle(isOn: $showSonnetUsage) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Sonnet Usage")
                            .font(.callout)
                        Text("Display weekly Sonnet usage in the popover.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @EnvironmentObject var usageService: UsageService
    @AppStorage("refreshMode") private var refreshMode: String = "smart"
    @AppStorage("refreshInterval") private var refreshInterval: Double = 300
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 12) {
            // Refresh Mode
            CardView {
                Label("Refresh Mode", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("", selection: $refreshMode) {
                    Text("Smart").tag("smart")
                    Text("Fixed").tag("fixed")
                }
                .pickerStyle(.segmented)

                if refreshMode == "smart" {
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
                            Text("Current: \(formatInterval(usageService.currentRefreshInterval))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Picker("Interval", selection: $refreshInterval) {
                        Text("5 Minutes").tag(300.0)
                        Text("10 Minutes").tag(600.0)
                        Text("30 Minutes").tag(1800.0)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: refreshInterval) {
                        usageService.startAutoRefresh(interval: refreshInterval)
                    }
                }
            }

            // Launch at Login
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
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("warningThreshold") private var warningThreshold: Double = 75
    @AppStorage("criticalThreshold") private var criticalThreshold: Double = 90
    @AppStorage("notifyOnReset") private var notifyOnReset: Bool = true
    @AppStorage("notifyOnStatusChange") private var notifyOnStatusChange: Bool = true
    @State private var testSent = false
    @State private var permissionStatus: String = "Checking..."
    @State private var permissionDenied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Enable + Permission
                CardView {
                    Toggle(isOn: $notificationsEnabled) {
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
                .onChange(of: notificationsEnabled) {
                    if notificationsEnabled { requestAndCheck() }
                }

                // Thresholds
                CardView {
                    Label("Thresholds", systemImage: "chart.bar.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Warning")
                                .font(.callout)
                            Spacer()
                            Text("\(Int(warningThreshold))%")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundColor(.orange)
                        }
                        Slider(value: $warningThreshold, in: 50...90, step: 5)
                            .tint(.orange)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Critical")
                                .font(.callout)
                            Spacer()
                            Text("\(Int(criticalThreshold))%")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundColor(.red)
                        }
                        Slider(value: $criticalThreshold, in: 75...100, step: 5)
                            .tint(.red)
                    }

                    if criticalThreshold <= warningThreshold {
                        Label("Critical must be higher than Warning.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .opacity(notificationsEnabled ? 1 : 0.5)
                .disabled(!notificationsEnabled)

                // Events
                CardView {
                    Label("Events", systemImage: "bell.badge")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle(isOn: $notifyOnReset) {
                        Text("Notify on usage reset")
                            .font(.callout)
                    }

                    Toggle(isOn: $notifyOnStatusChange) {
                        Text("Notify on status incidents")
                            .font(.callout)
                    }
                }
                .opacity(notificationsEnabled ? 1 : 0.5)
                .disabled(!notificationsEnabled)

                // Test
                CardView {
                    HStack {
                        Button(action: sendTestNotification) {
                            Label("Send Test Notification", systemImage: "paperplane")
                        }
                        .disabled(!notificationsEnabled)

                        if testSent {
                            Label("Sent", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
                .opacity(notificationsEnabled ? 1 : 0.5)
                .disabled(!notificationsEnabled)
            }
            .padding()
        }
    }

    private func checkPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
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
    }

    private func requestAndCheck() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            DispatchQueue.main.async { checkPermission() }
        }
    }

    private func sendTestNotification() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                checkPermission()
                guard granted else { return }

                let content = UNMutableNotificationContent()
                content.title = "CC Usage Bar"
                content.body = "Test notification successful!"
                content.sound = .default

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                let request = UNNotificationRequest(identifier: "test-\(UUID())", content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request)
            }
        }

        testSent = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { testSent = false }
    }
}

// MARK: - Status Tab

struct StatusTab: View {
    @EnvironmentObject var statusService: StatusService

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Live status of Claude services powered by the Anthropic status page. The main popover only shows a warning when there is an active incident.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                CardView {
                    HStack {
                        Image(systemName: statusService.status.emoji)
                            .font(.title3)
                        Text(statusService.statusDescription)
                            .fontWeight(.medium)
                        Spacer()
                        Button(action: {
                            Task { await statusService.fetchStatus() }
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                    }
                }

                if !statusService.components.isEmpty {
                    CardView {
                        Label("Components", systemImage: "server.rack")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ForEach(Array(statusService.components.enumerated()), id: \.offset) { _, component in
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
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    private let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            ClaudeLogoShape()
                .fill(Color(nsColor: NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)))
                .frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

            Text("CC Usage Bar")
                .font(.system(size: 22, weight: .semibold))

            Text("Version \(version) (\(build))")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Claude Code usage in your menu bar.")
                .font(.callout)
                .foregroundColor(.secondary)

            Link(destination: URL(string: "https://github.com/konradmichalik/cc-usage-bar")!) {
                Label("Project on GitHub", systemImage: "link")
            }
            .buttonStyle(.bordered)

            Spacer()

            Text("\u{00A9} 2026 Konrad Michalik")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
