import Foundation

// MARK: - API Response (chatgpt.com/backend-api/wham/usage)

/// Shape of the undocumented endpoint the Codex CLI itself uses for `/status`, mirrored from
/// `codex-backend-openapi-models` in `openai/codex`. Every field is optional on purpose: the
/// endpoint is not a public contract and new plans keep adding or dropping windows.
struct CodexUsageResponse: Decodable, Sendable {
    let planType: String?
    let rateLimit: CodexRateLimit?
    let credits: CodexCredits?
    let additionalRateLimits: [CodexAdditionalRateLimit]?
    let rateLimitReachedType: CodexRateLimitReachedType?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
        case additionalRateLimits = "additional_rate_limits"
        case rateLimitReachedType = "rate_limit_reached_type"
    }
}

struct CodexRateLimit: Decodable, Sendable {
    let allowed: Bool?
    let limitReached: Bool?
    let primaryWindow: CodexRateLimitWindow?
    let secondaryWindow: CodexRateLimitWindow?

    enum CodingKeys: String, CodingKey {
        case allowed
        case limitReached = "limit_reached"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }

    var windows: [CodexRateLimitWindow] {
        [primaryWindow, secondaryWindow].compactMap { $0 }
    }
}

struct CodexRateLimitWindow: Decodable, Sendable {
    let usedPercent: Double
    let limitWindowSeconds: Int
    let resetAt: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }
}

struct CodexCredits: Decodable, Sendable {
    let hasCredits: Bool?
    let unlimited: Bool?
    let balance: String?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }
}

struct CodexAdditionalRateLimit: Decodable, Sendable {
    let limitName: String
    let rateLimit: CodexRateLimit?

    enum CodingKeys: String, CodingKey {
        case limitName = "limit_name"
        case rateLimit = "rate_limit"
    }
}

struct CodexRateLimitReachedType: Decodable, Sendable {
    let type: String?
}

// MARK: - App Model

struct CodexNamedLimit: Sendable, Identifiable {
    let label: String
    let bucket: UsageBucket
    let windowSeconds: Int
    /// Index in `CodexUsage.additionalLimits`. Labels can repeat (same name and window twice).
    let position: Int

    var id: String { "\(position)-\(label)" }
}

/// Codex usage normalized onto Spark's existing `UsageData`, so the Claude rows, rings and
/// threshold logic render it unchanged.
struct CodexUsage: Sendable {
    let usageData: UsageData
    let additionalLimits: [CodexNamedLimit]
    let planType: String?
    let creditsBalance: String?
    let limitReached: Bool

    /// Anything up to 6h counts as the session window, 6 to 8 days as the weekly one. Codex
    /// reports a 5h and a 7d window on paid plans, but Pro has no 5h window and sends the weekly
    /// one as `primary_window`, and Free sends a single 30-day window. So neither the slot
    /// position nor "long means weekly" can decide the label.
    private static let sessionWindowMax = 6 * 3600
    private static let weeklyWindowRange = (6 * 86400)...(8 * 86400)

    init(response: CodexUsageResponse, now: Date = Date()) {
        var session: UsageBucket?
        var weekly: UsageBucket?
        var additional: [CodexNamedLimit] = []

        for window in response.rateLimit?.windows ?? [] {
            let bucket = Self.bucket(for: window)
            if window.limitWindowSeconds <= Self.sessionWindowMax, session == nil {
                session = bucket
            } else if Self.weeklyWindowRange.contains(window.limitWindowSeconds), weekly == nil {
                weekly = bucket
            } else {
                additional.append(CodexNamedLimit(
                    label: Self.windowName(window.limitWindowSeconds),
                    bucket: bucket,
                    windowSeconds: window.limitWindowSeconds,
                    position: additional.count
                ))
            }
        }

        for extra in response.additionalRateLimits ?? [] {
            for window in extra.rateLimit?.windows ?? [] {
                additional.append(CodexNamedLimit(
                    label: "\(extra.limitName) (\(Self.windowName(window.limitWindowSeconds)))",
                    bucket: Self.bucket(for: window),
                    windowSeconds: window.limitWindowSeconds,
                    position: additional.count
                ))
            }
        }

        usageData = UsageData(session: session, weekly: weekly, lastUpdated: now)
        additionalLimits = additional
        planType = response.planType
        limitReached = response.rateLimit?.limitReached == true || response.rateLimitReachedType != nil

        let credits = response.credits
        if credits?.hasCredits == true, credits?.unlimited != true, let balance = credits?.balance {
            creditsBalance = balance
        } else {
            creditsBalance = nil
        }
    }

    /// Highest usage across every window, including the ones that are neither session nor
    /// weekly, so a plan whose only quota is a 30-day window still drives the menu bar.
    var maxUtilization: Double {
        additionalLimits.map(\.bucket.utilization).reduce(usageData.maxUtilization, max)
    }

    /// "plus" → "Plus", "self_serve_business_prolite" → "Self Serve Business Prolite".
    var planDisplayName: String? {
        guard let planType, !planType.isEmpty else { return nil }
        return planType
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private static func bucket(for window: CodexRateLimitWindow) -> UsageBucket {
        let resetsAt = window.resetAt.map {
            ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval($0)))
        }
        return UsageBucket(utilization: window.usedPercent, resetsAt: resetsAt)
    }

    private static func windowName(_ seconds: Int) -> String {
        switch seconds {
        case 604_800: return "Weekly"
        case 86_400: return "Daily"
        case let value where value % 86_400 == 0: return "\(value / 86_400) days"
        case let value where value % 3600 == 0: return "\(value / 3600)h"
        default: return "\(max(seconds / 60, 1)) min"
        }
    }
}
