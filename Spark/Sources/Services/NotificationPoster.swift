import AppKit
import UserNotifications

/// Delivers a `SparkNotice`: its words, its provider's thread, the ring attachment, and the
/// provider whose tab a click opens (docs/design/rules.md, "Notifications").
@MainActor
enum NotificationPoster {
    /// `userInfo` key holding the `UsageProvider` raw value of the tab to open.
    nonisolated static let providerKey = "provider"

    static func post(_ notice: SparkNotice, id: String) {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = .default
        content.threadIdentifier = notice.thread
        if let provider = notice.provider {
            content.userInfo = [providerKey: provider.rawValue]
        }
        if let ring = notice.ring, let attachment = attachment(for: ring) {
            content.attachments = [attachment]
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    /// Writes the ring to a temporary PNG. The notification center moves the file into its own
    /// store when the attachment is created, so nothing piles up in the temporary folder.
    private static func attachment(for ring: NotificationRing) -> UNNotificationAttachment? {
        guard let data = ring.pngData(appearance: NSApp.effectiveAppearance) else { return nil }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SparkNotifications", isDirectory: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString).png")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url)
            return try UNNotificationAttachment(
                identifier: "ring", url: url, options: [UNNotificationAttachmentOptionsTypeHintKey: "public.png"]
            )
        } catch {
            return nil
        }
    }
}
