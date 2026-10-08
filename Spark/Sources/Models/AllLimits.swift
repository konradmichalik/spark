import Foundation

/// One line of the All Limits screen: a label, the value with its dot bar, and the reset in a
/// tooltip. `detail` replaces the percent for lines that are an amount rather than a share.
struct LimitLine: Equatable, Identifiable {
    let label: String
    let value: Double?
    let tone: UsageTone
    var elapsed: Double?
    var tooltip: String?
    var detail: String?

    var id: String { label }
}

/// The limits of a plan, then the lines that are paid on top of it (extra usage, credits),
/// which the screen sets apart.
struct LimitSections: Equatable {
    let limits: [LimitLine]
    let extras: [LimitLine]
}

enum AllLimits {
    private static let fiveHours: TimeInterval = 5 * 3600
    private static let sevenDays: TimeInterval = 7 * 86_400

    static func claude(
        _ data: UsageData, models: [ModelFamily], localTokens: [ModelFamily: Int],
        warning: Double, critical: Double, now: Date = Date(), locale: Locale = .current
    ) -> LimitSections {
        let line = { (label: String, bucket: UsageBucket, window: TimeInterval) in
            usageLine(label, bucket, window: window, warning: warning, critical: critical, now: now, locale: locale)
        }
        var limits: [LimitLine] = []
        if let session = data.session { limits.append(line("Session · 5h", session, fiveHours)) }
        if let weekly = data.weekly { limits.append(line("Week · all models", weekly, sevenDays)) }
        for family in models {
            let label = "Week · \(name(of: family))"
            if let bucket = bucket(of: family, in: data) {
                limits.append(line(label, bucket, sevenDays))
            } else if let tokens = localTokens[family], tokens > 0 {
                // The plan has no limit for this model, but local use still says something.
                limits.append(LimitLine(
                    label: label, value: nil, tone: .normal,
                    tooltip: "No separate limit on this plan. Tokens used on this Mac in the statistics period.",
                    detail: "\(formatTokenCount(tokens)) local"
                ))
            }
        }
        return LimitSections(limits: limits, extras: extraUsage(data.extraUsage, warning: warning, critical: critical))
    }

    static func codex(
        _ usage: CodexUsage, warning: Double, critical: Double, now: Date = Date(), locale: Locale = .current
    ) -> LimitSections {
        let line = { (label: String, bucket: UsageBucket, window: TimeInterval) in
            usageLine(label, bucket, window: window, warning: warning, critical: critical, now: now, locale: locale)
        }
        var limits: [LimitLine] = []
        if let session = usage.usageData.session { limits.append(line("Session · 5h", session, fiveHours)) }
        if let weekly = usage.usageData.weekly { limits.append(line("Week", weekly, sevenDays)) }
        for limit in usage.additionalLimits {
            limits.append(line(limit.label, limit.bucket, TimeInterval(limit.windowSeconds)))
        }
        let credits = usage.creditsBalance.map {
            LimitLine(label: "Credits", value: nil, tone: .normal, tooltip: "Credit balance of the ChatGPT account", detail: $0)
        }
        return LimitSections(limits: limits, extras: credits.map { [$0] } ?? [])
    }

    // swiftlint:disable:next function_parameter_count
    private static func usageLine(
        _ label: String, _ bucket: UsageBucket, window: TimeInterval, warning: Double, critical: Double, now: Date, locale: Locale
    ) -> LimitLine {
        let value = bucket.utilization
        let left = "\(UsageFormat.percent(max(100 - value, 0), locale: locale)) left"
        let reset = bucket.resetsAtDate.map { "Resets \($0.resetDescription)" }
        return LimitLine(
            label: label, value: value, tone: UsageTone(value: value, warning: warning, critical: critical),
            elapsed: Pace.calculate(utilization: value, resetsAt: bucket.resetsAtDate, windowLength: window, now: now)?.elapsedFraction,
            tooltip: [reset, left].compactMap { $0 }.joined(separator: "\n")
        )
    }

    private static func extraUsage(_ extra: ExtraUsage?, warning: Double, critical: Double) -> [LimitLine] {
        guard let extra, extra.hasSpend, let spend = extra.spendWithLimit else { return [] }
        let share = extra.utilization ?? extra.spendAmount.flatMap { spent in extra.limitAmount.map { spent / $0 * 100 } }
        return [LimitLine(
            label: "Extra usage", value: share, tone: UsageTone(value: share ?? 0, warning: warning, critical: critical),
            tooltip: "Billed on top of the plan, up to the monthly limit", detail: spend
        )]
    }

    private static func name(of family: ModelFamily) -> String {
        switch family {
        case .sonnet: "Sonnet"
        case .opus: "Opus"
        case .fable: "Fable"
        case .other: "Other"
        }
    }

    private static func bucket(of family: ModelFamily, in data: UsageData) -> UsageBucket? {
        switch family {
        case .sonnet: data.weeklySonnet
        case .opus: data.weeklyOpus
        case .fable: data.weeklyFable
        case .other: nil
        }
    }
}
