import os
import SwiftUI

extension CodexState {
    private static let statusLog = Logger(subsystem: "com.konradmichalik.spark", category: "codex-status")

    /// The OpenAI status page needs no sign-in, so it is also read while the usage poll is rate limited.
    func fetchStatus() async {
        guard isActive else { return }
        var snapshot: CodexStatusSnapshot?
        do {
            snapshot = try await Task.detached { try await CodexStatusClient.fetchStatus() }.value
        } catch {
            Self.statusLog.error("fetchStatus failed: \(error.localizedDescription, privacy: .public)")
        }
        guard isActive else { return }
        status = snapshot ?? .unavailable
        // A failed read keeps `lastStatusNotification`, so a flaky connection cannot notify one incident twice.
        if snapshot != nil { checkStatusNotification() }
    }

    private func checkStatusNotification() {
        let defaults = UserDefaults.standard
        let current = status.overall
        let enabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
            && defaults.object(forKey: "notifyOnStatusChange") as? Bool ?? true
        if ClaudeServiceStatus.shouldNotify(enabled: enabled, current: current, last: lastStatusNotification) {
            NotificationPoster.post(NoticeWording.codexStatus(current.displayName), id: "codex-status-\(current.rawValue)")
        }
        lastStatusNotification = current
    }
}
