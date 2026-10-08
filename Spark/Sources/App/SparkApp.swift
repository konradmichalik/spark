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

    /// A click on a provider's notification opens the popover on that provider's tab.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let provider = response.notification.request.content.userInfo[NotificationPoster.providerKey] as? String
        Task { @MainActor in
            if let provider, UsageProvider(rawValue: provider) != nil {
                UserDefaults.standard.set(provider, forKey: UsageProvider.selectionKey)
            }
            Self.openPopover()
        }
        completionHandler()
    }

    /// The menu bar extra has no API to open its window, so this clicks its status item button.
    private static func openPopover() {
        for window in NSApp.windows where window.className.contains("NSStatusBarWindow") {
            if let button = window.contentView?.firstSubview(of: NSStatusBarButton.self) {
                button.performClick(nil)
                return
            }
        }
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

private extension NSView {
    func firstSubview<T: NSView>(of type: T.Type) -> T? {
        if let match = self as? T { return match }
        for subview in subviews {
            if let match = subview.firstSubview(of: type) { return match }
        }
        return nil
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
            MenuBarView()
                .environmentObject(state)
                .environmentObject(codex)
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
                .environmentObject(codex)
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
    @State private var now = Date()
    /// One shared timer, so re-rendering the label does not restart it. It only triggers a
    /// re-render; the staleness check reads the current time itself.
    private static let minuteTick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    /// The value a rise fades in from, and how far the fade has run. `nil` outside a fade.
    @State private var fade: (from: Double, progress: Double)?
    @State private var fadeTask: Task<Void, Never>?

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

    private var connection: MenuBarConnection {
        switch reading.provider {
        case .codex:
            MenuBarConnection.codex(
                needsSignIn: codex.needsSignIn, hasError: codex.lastError != nil && !codex.isRateLimited,
                lastUpdated: codex.usage?.usageData.lastUpdated
            )
        case .claude:
            MenuBarConnection.claude(
                isAuthenticated: state.isAuthenticated, needsReconnect: state.needsReconnect,
                hasError: state.lastError != nil && !state.isRateLimited, lastUpdated: state.usageData.lastUpdated
            )
        }
    }

    private func isDimmed(now: Date) -> Bool {
        // Codex is the selected tab but has no data yet: the label shows Claude as a fallback.
        if UsageProvider(rawValue: selectedProviderRaw) == .codex, codex.isActive, codex.usage == nil {
            return true
        }
        return connection.isStale(now: now)
    }

    private func accessibilityText(dimmed: Bool) -> String {
        let provider = reading.provider == .codex ? "Codex" : "Claude"
        var text = "Spark, \(provider) \(reading.text)"
        switch tone {
        case .warning: text += ", warning"
        case .critical: text += ", critical"
        default: break
        }
        if connection.isDisconnected {
            text += ", disconnected"
        } else if dimmed {
            text += ", not up to date"
        }
        return text
    }

    var body: some View {
        let dimmed = isDimmed(now: max(now, Date()))
        let alpha: CGFloat = dimmed ? 0.35 : 1
        let glyph = MenuBarGlyph(value: reading.value, tone: tone, fadingFrom: fade?.from, progress: fade?.progress ?? 1)
        HStack(spacing: 5) {
            Image(nsImage: glyph.image(logo: logo, alpha: alpha))
            if state.menuBarValue != "none" {
                Text(reading.text)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle((tone == .normal ? Color.primary : tone.color).opacity(alpha))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(dimmed: dimmed))
        .onReceive(Self.minuteTick) { now = $0 }
        .onChange(of: reading.value) { old, new in fadeIn(from: old, to: new) }
    }

    /// A rise fades the new dots in with two in-between images, then stops. Started only by a
    /// value change, never at launch, and never a loop: a `TimelineView` in this label hung the
    /// app at launch once.
    private func fadeIn(from old: Double, to new: Double) {
        fadeTask?.cancel()
        fade = nil
        guard new > old, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        fadeTask = Task { @MainActor in
            for progress in MenuBarGlyph.fadeSteps {
                fade = (old, progress)
                try? await Task.sleep(for: MenuBarGlyph.fadeFrame)
                guard !Task.isCancelled else { return }
            }
            fade = nil
        }
    }
}
