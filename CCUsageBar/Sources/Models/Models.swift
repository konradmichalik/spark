import Foundation

// MARK: - API Response Models

struct OrganizationResponse: Codable {
    let uuid: String
    let name: String
}

struct UsageAPIResponse: Codable {
    let fiveHour: UsageBucket?
    let sevenDay: UsageBucket?
    let sevenDaySonnet: UsageBucket?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
    }
}

struct UsageBucket: Codable {
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
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - App Models

enum UsageLevel: String {
    case ok, warning, critical

    var color: String {
        switch self {
        case .ok: return "green"
        case .warning: return "yellow"
        case .critical: return "red"
        }
    }

    var threshold: Double {
        switch self {
        case .ok: return 0
        case .warning: return 75
        case .critical: return 90
        }
    }
}

struct UsageData {
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

struct UsageSnapshot: Codable, Identifiable {
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

// MARK: - Claude Status

enum ClaudeServiceStatus: String, Codable {
    case operational = "operational"
    case none = "none" // "none" means all systems operational
    case degradedPerformance = "degraded_performance"
    case partialOutage = "partial_outage"
    case majorOutage = "major_outage"
    case unknown

    var displayName: String {
        switch self {
        case .operational, .none: return "Operational"
        case .degradedPerformance: return "Degraded"
        case .partialOutage: return "Partial Outage"
        case .majorOutage: return "Major Outage"
        case .unknown: return "Unknown"
        }
    }

    var isHealthy: Bool {
        self == .operational || self == .none
    }

    var emoji: String {
        switch self {
        case .operational, .none: return "checkmark.circle.fill"
        case .degradedPerformance: return "exclamationmark.triangle.fill"
        case .partialOutage: return "bolt.trianglebadge.exclamationmark.fill"
        case .majorOutage: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

struct StatusPageResponse: Codable {
    let status: StatusIndicator
    let components: [StatusComponent]?
}

struct StatusIndicator: Codable {
    let indicator: String
    let description: String
}

struct StatusComponent: Codable {
    let name: String
    let status: String
}

// MARK: - Settings

struct AppSettings: Codable {
    var sessionKey: String = ""
    var organizationId: String = ""
    var refreshInterval: TimeInterval = 60
    var warningThreshold: Double = 75
    var criticalThreshold: Double = 90
    var notificationsEnabled: Bool = true
    var launchAtLogin: Bool = false

    static let defaultSettings = AppSettings()
}
