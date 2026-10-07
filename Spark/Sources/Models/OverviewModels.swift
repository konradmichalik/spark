import Foundation

/// What the session bar draws for the projection: hollow dots up to `projected`, red when the
/// limit is reached before the reset (docs/design/rules.md, "Dot language").
struct SessionForecast: Equatable {
    let projected: Double?
    let reachesLimit: Bool

    init(projected: Double?, reachesLimit: Bool) {
        self.projected = projected
        self.reachesLimit = reachesLimit
    }

    init(_ projection: ProjectionResult) {
        switch projection {
        case .safe(let value): self.init(projected: min(max(value, 0), 100), reachesLimit: false)
        case .limitReached: self.init(projected: 100, reachesLimit: true)
        case .insufficientData: self.init(projected: nil, reachesLimit: false)
        }
    }
}

struct HistoryColumn: Equatable {
    let session: Double?
    let weekly: Double?
}

/// Buckets snapshots of the last `window` into `count` equal slots, oldest first, keeping the
/// latest snapshot per slot. Slots without a snapshot stay empty instead of being stretched.
enum HistoryColumns {
    static func make(_ snapshots: [UsageSnapshot], now: Date, window: TimeInterval = 6 * 3600, count: Int = 34) -> [HistoryColumn] {
        guard count > 0, window > 0 else { return [] }
        let start = now.addingTimeInterval(-window)
        let slot = window / Double(count)
        var latest = [Int: UsageSnapshot]()
        for snapshot in snapshots where snapshot.timestamp >= start && snapshot.timestamp <= now {
            let index = min(Int(snapshot.timestamp.timeIntervalSince(start) / slot), count - 1)
            if let existing = latest[index], existing.timestamp > snapshot.timestamp { continue }
            latest[index] = snapshot
        }
        return (0..<count).map { index in
            guard let snapshot = latest[index] else { return HistoryColumn(session: nil, weekly: nil) }
            return HistoryColumn(session: snapshot.sessionUtilization, weekly: snapshot.weeklyUtilization)
        }
    }
}

/// Short values for the overview rows (docs/design/rules.md, "Navigation").
enum OverviewSummary {
    static func statisticsValue(cost: Double?, messages: Int?) -> String? {
        if let cost {
            let parts = UsageFormat.cost(cost)
            return "≈ $\(parts.number)\(parts.unit.replacingOccurrences(of: "$", with: ""))"
        }
        guard let messages else { return nil }
        return messages == 1 ? "1 message" : "\(messages) messages"
    }

    static func limitsValue(extraLimits: Int, plan: String?) -> String? {
        if extraLimits > 0 { return "\(extraLimits) more" }
        return plan
    }
}
