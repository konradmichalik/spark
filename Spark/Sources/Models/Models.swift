import Foundation

// MARK: - API Response Models

struct UsageAPIResponse: Codable, Sendable {
    let fiveHour: UsageBucket?
    let sevenDay: UsageBucket?
    let sevenDaySonnet: UsageBucket?
    let sevenDayOpus: UsageBucket?
    let sevenDayFable: UsageBucket?
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
        case sevenDayFable = "seven_day_fable"
        case extraUsage = "extra_usage"
    }
}

/// Pay-as-you-go credit usage beyond plan limits (`extra_usage` in the API).
struct ExtraUsage: Codable, Sendable {
    let isEnabled: Bool
    let monthlyLimit: Double?
    let usedCredits: Double?
    let utilization: Double?
    let currency: String?
    let decimalPlaces: Int?
    let disabledReason: String?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
        case currency
        case decimalPlaces = "decimal_places"
        case disabledReason = "disabled_reason"
    }

    /// True when extra usage is active and the user has actually spent credits.
    var hasSpend: Bool { isEnabled && (usedCredits ?? 0) > 0 }

    /// The API sends amounts in minor units (e.g. cents); `decimal_places` says where
    /// the point goes (2 → divide by 100). A missing field (legacy responses) means the
    /// value is already in major units, so the divisor is 1.
    private var minorUnitDivisor: Double {
        guard let places = decimalPlaces, places > 0 else { return 1 }
        return pow(10, Double(places))
    }

    /// Actual spent amount in major currency units, honoring `decimal_places`.
    var spendAmount: Double? {
        guard let used = usedCredits, used > 0 else { return nil }
        return used / minorUnitDivisor
    }

    /// Monthly spend cap in major currency units, honoring `decimal_places`. Nil when
    /// the API reports no limit.
    var limitAmount: Double? {
        guard let limit = monthlyLimit, limit > 0 else { return nil }
        return limit / minorUnitDivisor
    }

    /// Localized currency string for the spent amount, e.g. "€39.88". Nil when nothing spent.
    var formattedSpend: String? {
        guard let amount = spendAmount else { return nil }
        return Self.currencyFormatter(currency, decimalPlaces: decimalPlaces).string(from: NSNumber(value: amount))
    }

    /// The spend with its cap, e.g. "39,88 of 40,00 €", shown on All Limits and read the same
    /// way by VoiceOver. Falls back to the bare spent amount when no limit is known.
    var spendWithLimit: String? {
        guard let parts = formattedParts else { return nil }
        guard let limit = parts.limit else { return formattedSpend }
        return "\(parts.spend) of \(limit)"
    }

    /// The spent amount (no currency symbol) and, when a limit exists, the limit as a
    /// full currency string, both honoring `decimal_places`.
    private var formattedParts: (spend: String, limit: String?)? {
        guard let spend = spendAmount else { return nil }
        let digits = decimalPlaces ?? 2
        let decimal = NumberFormatter()
        decimal.numberStyle = .decimal
        decimal.minimumFractionDigits = digits
        decimal.maximumFractionDigits = digits
        guard let spendString = decimal.string(from: NSNumber(value: spend)) else { return nil }
        guard let limit = limitAmount,
              let limitString = Self.currencyFormatter(currency, decimalPlaces: decimalPlaces)
                  .string(from: NSNumber(value: limit)) else {
            return (spendString, nil)
        }
        return (spendString, limitString)
    }

    private static func currencyFormatter(_ currency: String?, decimalPlaces: Int?) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency ?? "USD"
        if let decimalPlaces, decimalPlaces >= 0 {
            formatter.minimumFractionDigits = decimalPlaces
            formatter.maximumFractionDigits = decimalPlaces
        }
        return formatter
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
    var weeklyOpus: UsageBucket?
    var weeklyFable: UsageBucket?
    var extraUsage: ExtraUsage?
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

struct UsageSnapshot: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let sessionUtilization: Double
    let weeklyUtilization: Double
    /// Optional so snapshots written before these fields existed still decode.
    let sonnetUtilization: Double?
    let opusUtilization: Double?
    let fableUtilization: Double?
    let extraUsageSpend: Double?

    init(
        timestamp: Date = Date(),
        sessionUtilization: Double,
        weeklyUtilization: Double,
        sonnetUtilization: Double? = nil,
        opusUtilization: Double? = nil,
        fableUtilization: Double? = nil,
        extraUsageSpend: Double? = nil
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.sessionUtilization = sessionUtilization
        self.weeklyUtilization = weeklyUtilization
        self.sonnetUtilization = sonnetUtilization
        self.opusUtilization = opusUtilization
        self.fableUtilization = fableUtilization
        self.extraUsageSpend = extraUsageSpend
    }
}

// MARK: - Session Projection

enum ProjectionResult: Sendable {
    case limitReached(TimeInterval)
    case safe(Double)
    case insufficientData
}

enum SessionProjection {
    /// Minutes of data the rate needs before it is worth extrapolating to the reset.
    static let minimumSpan: TimeInterval = 15 * 60
    private static let sessionLength: TimeInterval = 5 * 3600

    /// Calculate projection from the last 60 minutes of the current session's snapshots, current
    /// utilization, and reset date. Snapshots from before the session started would mix two
    /// sessions into one rate, so they are dropped.
    static func calculate(
        history: [UsageSnapshot],
        currentUtilization: Double,
        resetsAt: Date?,
        now: Date = Date()
    ) -> ProjectionResult {
        guard let resetsAt else { return .insufficientData }

        let hoursUntilReset = resetsAt.timeIntervalSince(now) / 3600
        guard hoursUntilReset > 0 else { return .insufficientData }

        let cutoff = max(now.addingTimeInterval(-3600), resetsAt.addingTimeInterval(-sessionLength))
        let recent = history.filter { $0.timestamp > cutoff }

        guard recent.count >= 2,
              let oldest = recent.first,
              let newest = recent.last else {
            return .insufficientData
        }

        let span = newest.timestamp.timeIntervalSince(oldest.timestamp)
        guard span >= minimumSpan else { return .insufficientData }
        let timeDiffHours = span / 3600

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

/// What the popover knows about the service: the overall status and the two components it shows.
struct ServiceStatusSnapshot: Equatable {
    var overall: ClaudeServiceStatus
    var claudeCode: ClaudeServiceStatus
    var api: ClaudeServiceStatus
    var description: String

    /// After a failed fetch nothing is known, including components of an earlier incident.
    static let unavailable = ServiceStatusSnapshot(overall: .unknown, claudeCode: .unknown, api: .unknown, description: "Status unavailable")
}

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

    /// Reads both status page vocabularies: the overall indicator (`none`, `minor`, `major`,
    /// `critical`) and component statuses (`operational`, `degraded_performance`, …). Treating
    /// the indicator as a component status turned every real incident into `.unknown`.
    static func parse(_ raw: String) -> ClaudeServiceStatus {
        switch raw {
        case "minor", "maintenance", "under_maintenance": .degradedPerformance
        case "major": .partialOutage
        case "critical": .majorOutage
        default: ClaudeServiceStatus(rawValue: raw) ?? .unknown
        }
    }

    /// A notification is for a problem the status page reports, not for a failed fetch (`.unknown`).
    static func shouldNotify(enabled: Bool, current: ClaudeServiceStatus, last: ClaudeServiceStatus) -> Bool {
        enabled && current != last && current.isIncident
    }

    /// A problem the status page actually reports. `.unknown` only means the page could not be
    /// read, which is no reason to show a notice in the popover.
    var isIncident: Bool {
        self == .degradedPerformance || self == .partialOutage || self == .majorOutage
    }

    /// The status as one dot: quiet while healthy, pulsing in ochre or red during an incident,
    /// hollow while it cannot be read.
    var dot: StatusDot {
        switch self {
        case .operational, .none: StatusDot(tone: .normal, isHollow: false, pulses: false)
        case .degradedPerformance, .partialOutage: StatusDot(tone: .warning, isHollow: false, pulses: true)
        case .majorOutage: StatusDot(tone: .critical, isHollow: false, pulses: true)
        case .unknown: StatusDot(tone: .normal, isHollow: true, pulses: false)
        }
    }

    var icon: TablerIcon {
        switch self {
        case .operational, .none: .circleCheck
        case .degradedPerformance: .alertTriangle
        case .partialOutage: .alertTriangle
        case .majorOutage: .circleX
        case .unknown: .helpCircle
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

// MARK: - Claude Code Install Method

/// How the Claude Code CLI was installed, as recorded by the CLI itself in
/// `~/.claude.json`'s `installMethod` field. `native`, `local`, `standalone`, `unknown`,
/// and any unrecognized/missing value all collapse into `.other` — they self-update via
/// `claude update` and have no distinct remediation command to offer.
enum ClaudeCodeInstallMethod: String, Sendable {
    case npmGlobal
    case homebrew
    case other

    init(rawConfigValue: String?) {
        switch rawConfigValue {
        case "npm-global": self = .npmGlobal
        case "homebrew": self = .homebrew
        default: self = .other
        }
    }

    var displayLabel: String {
        switch self {
        case .npmGlobal: "npm"
        case .homebrew: "Homebrew"
        case .other: "native"
        }
    }

    var updateCommand: String {
        switch self {
        case .npmGlobal: "npm update -g @anthropic-ai/claude-code"
        case .homebrew: "brew upgrade --cask claude-code"
        case .other: "claude update"
        }
    }
}

struct StatusDot: Equatable {
    let tone: UsageTone
    let isHollow: Bool
    let pulses: Bool
}
