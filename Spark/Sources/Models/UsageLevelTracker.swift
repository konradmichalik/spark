import Foundation

/// Remembers each usage window's last level and reports the ones that moved into a warning or
/// critical level since the previous update. Every window is judged on its own, so a window that
/// is already notified never hides another one's rise.
struct UsageLevelTracker {
    struct Crossing: Equatable {
        let key: String
        let level: UsageLevel
        let utilization: Double
    }

    private var levels: [String: UsageLevel] = [:]

    /// `key` must be unique per window: labels can repeat, so Codex passes its position-based id.
    mutating func update(_ windows: [(key: String, utilization: Double)], warning: Double, critical: Double) -> [Crossing] {
        var crossings: [Crossing] = []
        for window in windows {
            let level: UsageLevel = window.utilization >= critical ? .critical : window.utilization >= warning ? .warning : .ok
            if level != .ok, level != levels[window.key, default: .ok] {
                crossings.append(Crossing(key: window.key, level: level, utilization: window.utilization))
            }
            levels[window.key] = level
        }
        return crossings
    }
}
