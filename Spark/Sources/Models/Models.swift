import Foundation

// MARK: - API Response Models

struct UsageAPIResponse: Codable, Sendable {
    let fiveHour: UsageBucket?
    let sevenDay: UsageBucket?
    let sevenDaySonnet: UsageBucket?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
    }
}

struct UsageBucket: Codable, Sendable {
    let utilization: Double // 0-100
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    var resetsAtDate: Date? {
        guard let resetsAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: resetsAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: resetsAt)
    }

    var timeUntilReset: String? {
        guard let date = resetsAtDate else { return nil }
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "now" }
        return interval.shortDuration
    }
}

// MARK: - App Models

enum UsageLevel: String, Sendable {
    case ok, warning, critical
}

struct UsageData: Sendable {
    var session: UsageBucket?
    var weekly: UsageBucket?
    var weeklySonnet: UsageBucket?
    var lastUpdated: Date = Date()

    var sessionUtilization: Double { session?.utilization ?? 0 }
    var weeklyUtilization: Double { weekly?.utilization ?? 0 }
    var maxUtilization: Double { max(sessionUtilization, weeklyUtilization) }

    var level: UsageLevel {
        let maxVal = maxUtilization
        let warning = UserDefaults.standard.object(forKey: "warningThreshold") as? Double ?? 75
        let critical = UserDefaults.standard.object(forKey: "criticalThreshold") as? Double ?? 90
        if maxVal >= critical { return .critical }
        if maxVal >= warning { return .warning }
        return .ok
    }

    static let empty = UsageData()
}

// MARK: - Usage History

struct UsageSnapshot: Codable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let sessionUtilization: Double
    let weeklyUtilization: Double

    init(timestamp: Date = Date(), sessionUtilization: Double, weeklyUtilization: Double) {
        self.id = UUID()
        self.timestamp = timestamp
        self.sessionUtilization = sessionUtilization
        self.weeklyUtilization = weeklyUtilization
    }
}

// MARK: - Session Projection

enum ProjectionResult: Sendable {
    case limitReached(TimeInterval)
    case safe(Double)
    case insufficientData
}

enum SessionProjection {
    /// Calculate projection from history snapshots (last 60 min), current utilization, and reset date.
    static func calculate(
        history: [UsageSnapshot],
        currentUtilization: Double,
        resetsAt: Date?
    ) -> ProjectionResult {
        guard let resetsAt else { return .insufficientData }

        let hoursUntilReset = resetsAt.timeIntervalSinceNow / 3600
        guard hoursUntilReset > 0 else { return .insufficientData }

        let cutoff = Date().addingTimeInterval(-3600) // last 60 minutes
        let recent = history.filter { $0.timestamp > cutoff }

        guard recent.count >= 2,
              let oldest = recent.first,
              let newest = recent.last else {
            return .insufficientData
        }

        let timeDiffHours = newest.timestamp.timeIntervalSince(oldest.timestamp) / 3600
        guard timeDiffHours > 0 else { return .insufficientData }

        let rate = (newest.sessionUtilization - oldest.sessionUtilization) / timeDiffHours
        guard rate > 0 else { return .insufficientData }

        let projectedAtReset = currentUtilization + (rate * hoursUntilReset)

        if projectedAtReset >= 100 {
            let hoursToLimit = (100 - currentUtilization) / rate
            return .limitReached(hoursToLimit * 3600)
        }

        return .safe(min(projectedAtReset, 100))
    }
}

// MARK: - Claude Status

enum ClaudeServiceStatus: String, Codable, Sendable {
    case operational = "operational"
    case none = "none"
    case degradedPerformance = "degraded_performance"
    case partialOutage = "partial_outage"
    case majorOutage = "major_outage"
    case unknown

    var displayName: String {
        switch self {
        case .operational, .none: "Operational"
        case .degradedPerformance: "Degraded"
        case .partialOutage: "Partial Outage"
        case .majorOutage: "Major Outage"
        case .unknown: "Unknown"
        }
    }

    var isHealthy: Bool {
        self == .operational || self == .none
    }

    var emoji: String {
        switch self {
        case .operational, .none: "checkmark.circle.fill"
        case .degradedPerformance: "exclamationmark.triangle.fill"
        case .partialOutage: "bolt.trianglebadge.exclamationmark.fill"
        case .majorOutage: "xmark.circle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }
}

struct StatusPageResponse: Codable, Sendable {
    let status: StatusIndicator
    let components: [StatusComponent]?
}

struct StatusIndicator: Codable, Sendable {
    let indicator: String
    let description: String
}

struct StatusComponent: Codable, Sendable {
    let name: String
    let status: String
}
