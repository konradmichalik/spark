import Foundation

/// When Codex's local stats are re-read. Bounded periods skip old files by modification date, so
/// the usage poll can keep them fresh. "All" parses every rollout file, so it only runs when
/// someone looks at it, and at most once per poll interval after that.
enum CodexStatsRefresh {
    enum Trigger {
        case poll
        case visit
    }

    static let minimumInterval: TimeInterval = 300

    static func shouldRefresh(period: StatsPeriod, trigger: Trigger, lastRefresh: Date?, now: Date) -> Bool {
        switch trigger {
        case .poll:
            return period != .all
        case .visit:
            guard let lastRefresh else { return true }
            return now.timeIntervalSince(lastRefresh) >= minimumInterval
        }
    }
}
