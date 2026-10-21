import Foundation

enum CodexBurnRateRefresh {
    /// The visible overview rescans at most this often. Nothing else triggers a scan: the burn
    /// rate is only shown there, so a background poll would read rollout files for nobody.
    static let minimumInterval: TimeInterval = 60

    static func shouldRefresh(lastRefresh: Date?, now: Date) -> Bool {
        guard let lastRefresh else { return true }
        return now.timeIntervalSince(lastRefresh) >= minimumInterval
    }

    static func canPublish(scanID: UUID, currentScanID: UUID, isActive: Bool) -> Bool {
        isActive && scanID == currentScanID
    }
}
