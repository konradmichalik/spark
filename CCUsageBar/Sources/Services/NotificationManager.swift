import Foundation
import UserNotifications

@MainActor
class NotificationManager: ObservableObject {
    private var lastSessionLevel: UsageLevel = .ok
    private var lastWeeklyLevel: UsageLevel = .ok
    private var lastStatusNotification: ClaudeServiceStatus = .operational
    private var lastSessionResetDate: Date?
    private var lastWeeklyResetDate: Date?

    init() {
        requestPermission()
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func checkAndNotify(usage: UsageData, status: ClaudeServiceStatus) {
        let enabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        guard enabled else { return }

        let warningThreshold = UserDefaults.standard.object(forKey: "warningThreshold") as? Double ?? 75
        let criticalThreshold = UserDefaults.standard.object(forKey: "criticalThreshold") as? Double ?? 90

        checkUsageNotification(
            label: "Session",
            utilization: usage.sessionUtilization,
            lastLevel: &lastSessionLevel,
            warningAt: warningThreshold,
            criticalAt: criticalThreshold
        )
        checkUsageNotification(
            label: "Weekly",
            utilization: usage.weeklyUtilization,
            lastLevel: &lastWeeklyLevel,
            warningAt: warningThreshold,
            criticalAt: criticalThreshold
        )
        checkStatusNotification(status: status)
        checkResetNotification(usage: usage)
    }

    private func checkUsageNotification(label: String, utilization: Double, lastLevel: inout UsageLevel, warningAt: Double, criticalAt: Double) {
        let newLevel = levelFor(utilization, warningAt: warningAt, criticalAt: criticalAt)
        if newLevel != lastLevel && newLevel != .ok {
            let title: String
            let body: String

            switch newLevel {
            case .warning:
                title = "\(label) usage at \(Int(utilization))%"
                body = "Claude Code \(label) limit approaching. \(100 - Int(utilization))% remaining."
            case .critical:
                title = "\(label) usage at \(Int(utilization))%"
                body = "Claude Code \(label) limit almost reached! Only \(100 - Int(utilization))% remaining."
            case .ok:
                return
            }

            sendNotification(id: "usage-\(label)-\(newLevel.rawValue)", title: title, body: body)
        }
        lastLevel = newLevel
    }

    private func checkStatusNotification(status: ClaudeServiceStatus) {
        let notifyOnStatus = UserDefaults.standard.object(forKey: "notifyOnStatusChange") as? Bool ?? true
        if notifyOnStatus && status != lastStatusNotification && !status.isHealthy {
            sendNotification(
                id: "status-\(status.rawValue)",
                title: "Claude Status: \(status.displayName)",
                body: "Claude Code is currently experiencing issues."
            )
        }
        lastStatusNotification = status
    }

    private func checkResetNotification(usage: UsageData) {
        let notifyOnReset = UserDefaults.standard.object(forKey: "notifyOnReset") as? Bool ?? true
        guard notifyOnReset else { return }

        // Session reset detection
        if let resetDate = usage.session?.resetsAtDate {
            if let lastDate = lastSessionResetDate, resetDate != lastDate, usage.sessionUtilization < 5 {
                sendNotification(
                    id: "reset-session",
                    title: "Session limit reset",
                    body: "Your Claude Code session usage has been reset."
                )
            }
            lastSessionResetDate = resetDate
        }

        // Weekly reset detection
        if let resetDate = usage.weekly?.resetsAtDate {
            if let lastDate = lastWeeklyResetDate, resetDate != lastDate, usage.weeklyUtilization < 5 {
                sendNotification(
                    id: "reset-weekly",
                    title: "Weekly limit reset",
                    body: "Your Claude Code weekly usage has been reset."
                )
            }
            lastWeeklyResetDate = resetDate
        }
    }

    private func levelFor(_ utilization: Double, warningAt: Double, criticalAt: Double) -> UsageLevel {
        if utilization >= criticalAt { return .critical }
        if utilization >= warningAt { return .warning }
        return .ok
    }

    private func sendNotification(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
