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
    @State private var hasLaunched = false

    var body: some Scene {
        MenuBarExtra {
            Group {
                if state.isAuthenticated {
                    MenuBarView()
                        .environmentObject(state)
                } else {
                    NotConnectedView()
                        .environmentObject(state)
                }
            }
            .task {
                guard !hasLaunched else { return }
                hasLaunched = true
                state.onLaunch()
            }
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: state.usageData.maxUtilization) {
            state.checkAndNotify()
        }
        .onChange(of: state.status) {
            state.checkAndNotify()
        }

        Settings {
            SettingsView()
                .environmentObject(state)
        }
    }
}

// MARK: - Menubar Label

struct MenuBarLabel: View {
    @ObservedObject var state: AppState

    private var displayValue: Double {
        switch state.menuBarValue {
        case "session": state.usageData.sessionUtilization
        case "weekly": state.usageData.weeklyUtilization
        default: state.usageData.maxUtilization
        }
    }

    private var iconColor: NSColor {
        if !state.status.isHealthy && state.status != .unknown {
            return .systemOrange
        }
        switch state.usageData.level {
        case .ok: return .systemGreen
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    private func makeIcon(draw: @escaping (CGRect) -> Void) -> NSImage {
        let size = CGSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            draw(rect)
            return true
        }
        image.isTemplate = !state.coloredIcon
        return image
    }

    private var sparkIcon: NSImage {
        let utilization = displayValue
        let size = CGSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let ringRadius: CGFloat = rect.width / 2 - 1
            let ringWidth: CGFloat = 1.8

            // Track (gray ring)
            let trackPath = NSBezierPath()
            trackPath.appendArc(withCenter: center, radius: ringRadius, startAngle: 0, endAngle: 360)
            trackPath.lineWidth = ringWidth
            NSColor.gray.withAlphaComponent(0.3).setStroke()
            trackPath.stroke()

            // Progress arc (starts at top, goes clockwise)
            if utilization > 0 {
                let startAngle: CGFloat = 90 // top
                let endAngle = 90 - (CGFloat(min(utilization, 100)) / 100 * 360)
                let arcPath = NSBezierPath()
                arcPath.appendArc(withCenter: center, radius: ringRadius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
                arcPath.lineWidth = ringWidth
                arcPath.lineCapStyle = .round
                self.iconColor.setStroke()
                arcPath.stroke()
            }

            // Spark shape in the center
            let sparkInset: CGFloat = 3.5
            let sparkRect = rect.insetBy(dx: sparkInset, dy: sparkInset)
            let sparkPath = ClaudeLogoShape().path(in: CGRect(origin: .zero, size: sparkRect.size))
            let transform = AffineTransform(translationByX: sparkRect.minX, byY: sparkRect.minY)
            let bezier = NSBezierPath(cgPath: sparkPath.cgPath)
            bezier.transform(using: transform)
            let sparkColor: NSColor = self.state.coloredIcon ? .labelColor : Theme.sparkOrangeNS
            sparkColor.setFill()
            bezier.fill()

            return true
        }
        image.isTemplate = !state.coloredIcon
        return image
    }

    private var barIcon: NSImage {
        let utilization = displayValue
        let imgSize = CGSize(width: 18, height: 12)
        let image = NSImage(size: imgSize, flipped: false) { rect in
            let barHeight: CGFloat = 5
            let barY = (rect.height - barHeight) / 2
            let cornerRadius: CGFloat = barHeight / 2

            // Track
            let trackRect = CGRect(x: 0, y: barY, width: rect.width, height: barHeight)
            let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.gray.withAlphaComponent(0.3).setFill()
            trackPath.fill()

            // Fill
            let fillWidth = max(0, rect.width * CGFloat(min(utilization, 100)) / 100)
            if fillWidth > 0 {
                let fillRect = CGRect(x: 0, y: barY, width: fillWidth, height: barHeight)
                let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: cornerRadius, yRadius: cornerRadius)
                self.iconColor.setFill()
                fillPath.fill()
            }

            return true
        }
        image.isTemplate = !state.coloredIcon
        return image
    }

    private var dotIcon: NSImage {
        makeIcon { rect in
            let dotSize: CGFloat = 10
            let dotRect = CGRect(
                x: (rect.width - dotSize) / 2,
                y: (rect.height - dotSize) / 2,
                width: dotSize,
                height: dotSize
            )
            let path = NSBezierPath(ovalIn: dotRect)
            self.iconColor.setFill()
            path.fill()
        }
    }

    private var percentageColor: Color {
        state.coloredIcon ? Color(nsColor: iconColor) : .primary
    }

    private var showPercentage: Bool {
        state.menuBarValue != "none"
    }

    @ViewBuilder
    private var percentageText: some View {
        Text("\(Int(displayValue))%")
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(percentageColor)
    }

    var body: some View {
        switch state.iconStyle {
        case "minimal":
            if showPercentage {
                percentageText
            } else {
                Image(nsImage: sparkIcon)
            }
        case "dot":
            HStack(spacing: 6) {
                Image(nsImage: dotIcon)
                    .frame(width: 16, height: 16)
                if showPercentage { percentageText }
            }
        case "bar":
            HStack(spacing: 6) {
                Image(nsImage: barIcon)
                if showPercentage { percentageText }
            }
        default:
            HStack(spacing: 6) {
                Image(nsImage: sparkIcon)
                if showPercentage { percentageText }
            }
        }
    }
}
