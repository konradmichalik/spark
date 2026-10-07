import AppKit
import SwiftUI
import UserNotifications

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var contextMenu: NSMenu?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        // Explicitly set app icon so macOS uses it in notifications (LSUIElement apps don't show it reliably otherwise)
        if let iconImage = NSImage(named: NSImage.applicationIconName) {
            NSApplication.shared.applicationIconImage = iconImage
        }
        setupContextMenu()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private func setupContextMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Spark", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        contextMenu = menu

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self, let menu = self.contextMenu else { return event }
            if let button = event.window?.contentView?.hitTest(event.locationInWindow) as? NSStatusBarButton {
                menu.popUp(positioning: nil, at: .zero, in: button)
                return nil
            }
            return event
        }
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct SparkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState()
    @StateObject private var codex = CodexState()
    @State private var hasLaunched = false

    var body: some Scene {
        MenuBarExtra {
            Group {
                if state.isAuthenticated {
                    MenuBarView()
                        .environmentObject(state)
                        .environmentObject(codex)
                } else {
                    NotConnectedView()
                        .environmentObject(state)
                }
            }
            .task {
                guard !hasLaunched else { return }
                hasLaunched = true
                state.onLaunch()
                codex.onLaunch()
            }
            .tooltipHost()
            .background(MenuBarWindowTopPinner())
        } label: {
            MenuBarLabel(state: state, codex: codex)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: state.usageData.maxUtilization) {
            state.checkAndNotify()
        }
        .onChange(of: state.status) {
            state.checkAndNotify()
        }
        // Every fetch, not just a changed maximum: a session warning can come due while an
        // already-notified weekly window keeps the maximum where it was.
        .onChange(of: codex.usage?.usageData.lastUpdated) {
            codex.checkAndNotify()
        }

        Settings {
            SettingsView()
                .environmentObject(state)
                .environmentObject(codex)
                .tooltipHost()
        }

        Window("Usage Report", id: WeeklyReportView.windowID) {
            WeeklyReportView()
                .environmentObject(state)
                .tooltipHost()
        }
        .windowResizability(.contentMinSize)
    }
}

// MARK: - Menubar Label

struct MenuBarLabel: View {
    @ObservedObject var state: AppState
    @ObservedObject var codex: CodexState
    @AppStorage(UsageProvider.selectionKey) private var selectedProviderRaw = UsageProvider.claude.rawValue

    private var reading: MenuBarReading {
        MenuBarReading.resolve(
            claude: state.usageData,
            codex: codex.isActive ? codex.usage : nil,
            value: state.menuBarValue,
            provider: UsageProvider(rawValue: selectedProviderRaw) ?? .claude
        )
    }

    private var tone: UsageTone {
        UsageTone(value: reading.value, warning: state.warningThreshold, critical: state.criticalThreshold)
    }

    private var logo: MenuBarLogo? {
        guard MenuBarIconStyle(stored: state.iconStyle) == .providerLogo else { return nil }
        return reading.provider == .codex ? .codex : .claude
    }

    /// No fresh value: the connection is lost, Codex needs a new sign-in, or the last update is
    /// older than an hour (polling runs every 5 to 30 minutes).
    private var isDimmed: Bool {
        if state.needsReconnect { return true }
        let lastUpdated: Date
        switch reading.provider {
        case .codex:
            if codex.needsSignIn { return true }
            lastUpdated = codex.usage?.usageData.lastUpdated ?? .distantPast
        case .claude:
            lastUpdated = state.usageData.lastUpdated
        }
        return Date().timeIntervalSince(lastUpdated) > 3600
    }

    private var accessibilityText: String {
        let provider = reading.provider == .codex ? "Codex" : "Claude"
        let status = state.needsReconnect ? ", disconnected" : isDimmed ? ", not up to date" : ""
        return "Spark, \(provider) \(reading.text)\(status)"
    }

    var body: some View {
        let glyph = MenuBarGlyph(value: reading.value, tone: tone)
        HStack(spacing: 5) {
            Image(nsImage: glyph.image(logo: logo))
            if state.menuBarValue != "none" {
                Text(reading.text)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tone == .normal ? Color.primary : tone.color)
            }
        }
        .opacity(isDimmed ? 0.35 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}
