import AppKit
import SwiftUI
import UserNotifications

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@main
struct CCUsageBarApp: App {
    @StateObject private var usageService = UsageService()
    @StateObject private var statusService = StatusService()
    @StateObject private var notificationManager = NotificationManager()
    @AppStorage("iconStyle") private var iconStyle: String = "logo"
    @AppStorage("menuBarValue") private var menuBarValue: String = "max"
    private let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        MenuBarExtra {
            if usageService.isAuthenticated {
                MenuBarView()
                    .environmentObject(usageService)
                    .environmentObject(statusService)
            } else {
                VStack(spacing: 12) {
                    Text("CC Usage Bar")
                        .font(.headline)
                    Text("Not connected")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    SettingsLink {
                        Text("Log In / Settings...")
                    }

                    if let error = usageService.error {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.red)
                    }

                    Divider()

                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                }
                .padding()
                .frame(width: 250)
            }
        } label: {
            MenuBarLabel(
                usageData: usageService.usageData,
                status: statusService.status,
                iconStyle: iconStyle,
                menuBarValue: menuBarValue
            )
        }
        .menuBarExtraStyle(.window)
        .onChange(of: usageService.usageData.maxUtilization) {
            notificationManager.checkAndNotify(
                usage: usageService.usageData,
                status: statusService.status
            )
        }
        .onChange(of: statusService.status) {
            notificationManager.checkAndNotify(
                usage: usageService.usageData,
                status: statusService.status
            )
        }

        Settings {
            SettingsView()
                .environmentObject(usageService)
                .environmentObject(statusService)
        }
    }
}

// MARK: - Menubar Label

struct MenuBarLabel: View {
    let usageData: UsageData
    let status: ClaudeServiceStatus
    let iconStyle: String
    let menuBarValue: String

    private var displayValue: Double {
        switch menuBarValue {
        case "session": return usageData.sessionUtilization
        case "weekly": return usageData.weeklyUtilization
        default: return usageData.maxUtilization
        }
    }

    private var iconColor: NSColor {
        if !status.isHealthy && status != .unknown {
            return .systemOrange
        }
        switch usageData.level {
        case .ok: return .systemGreen
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    private func coloredImage(draw: @escaping (CGRect) -> Void) -> NSImage {
        let size = CGSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            draw(rect)
            return true
        }
        image.isTemplate = false
        return image
    }

    private var claudeIcon: NSImage {
        coloredImage { rect in
            let path = ClaudeLogoShape().path(in: rect)
            let bezier = NSBezierPath(cgPath: path.cgPath)
            self.iconColor.setFill()
            bezier.fill()
        }
    }

    private var dotIcon: NSImage {
        coloredImage { rect in
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

    var body: some View {
        switch iconStyle {
        case "minimal":
            Text("\(Int(displayValue))%")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Color(nsColor: iconColor))
        case "dot":
            HStack(spacing: 6) {
                Image(nsImage: dotIcon)
                    .frame(width: 16, height: 16)
                Text("\(Int(displayValue))%")
                    .font(.system(.caption, design: .monospaced))
            }
        default: // "logo"
            HStack(spacing: 6) {
                Image(nsImage: claudeIcon)
                Text("\(Int(displayValue))%")
                    .font(.system(.caption, design: .monospaced))
            }
        }
    }
}
