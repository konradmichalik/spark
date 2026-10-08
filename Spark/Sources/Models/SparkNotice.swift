import Foundation

/// The twelve-dot ring attached to a usage notification (docs/design/rules.md, "Notifications"):
/// filled like the menu bar glyph and coloured by state. A reset gets an empty ink ring.
enum NotificationRing: Equatable {
    case usage(value: Double, tone: UsageTone)
    case reset

    var value: Double {
        switch self {
        case .usage(let value, _): value
        case .reset: 0
        }
    }

    var tone: UsageTone {
        switch self {
        case .usage(_, let tone): tone
        case .reset: .normal
        }
    }

    var opacities: [Double] {
        DotRingLayout.partialOpacities(count: MenuBarGlyph.dotCount, value: value)
    }

    /// The number in the ring's centre, without a unit.
    var label: String {
        let clamped = value.isFinite ? min(max(value, 0), 100) : 0
        return String(Int(clamped.rounded()))
    }
}

/// One notification's words, thread and attachment.
struct SparkNotice: Equatable {
    let title: String
    let body: String
    /// One thread per provider, so Claude and Codex do not mix in Notification Center.
    let thread: String
    var ring: NotificationRing?
    /// The tab a click opens; `nil` for messages about Spark itself.
    var provider: UsageProvider?
}

/// The wording of every notification Spark sends. Title: provider and window, then the value.
/// Body: the one thing to act on.
enum NoticeWording {
    static let appThread = "spark"

    // swiftlint:disable:next function_parameter_count
    static func usage(
        provider: UsageProvider, window: String, value: Double, tone: UsageTone, resetsAt: Date?, limitIn: TimeInterval?,
        now: Date = Date(), locale: Locale = .current, timeZone: TimeZone = .current
    ) -> SparkNotice {
        let reset = resetsAt.map { max($0.timeIntervalSince(now), 0) }
        let body: String
        if let limitIn {
            let resetText = reset.map { " Resets in \($0.shortDuration)." } ?? ""
            body = "At this pace the limit is reached in ~\(limitIn.shortDuration).\(resetText)"
        } else {
            let left = "\(UsageFormat.percent(max(100 - value, 0), locale: locale)) left"
            switch (reset, resetsAt) {
            case let (.some(seconds), .some(date)) where seconds >= 86_400:
                body = "\(left) until \(ReportText.format(date, template: "EEEjmm", locale: locale, timeZone: timeZone))."
            case let (.some(seconds), _):
                body = "\(left). Resets in \(seconds.shortDuration)."
            default:
                body = "\(left)."
            }
        }
        return SparkNotice(
            title: "\(provider.segmentLabel) · \(window) at \(UsageFormat.percent(value, locale: locale))",
            body: body, thread: provider.rawValue, ring: .usage(value: value, tone: tone), provider: provider
        )
    }

    static func reset(
        provider: UsageProvider, window: String, nextReset: Date?,
        now: Date = Date(), locale: Locale = .current, timeZone: TimeZone = .current
    ) -> SparkNotice {
        var body = "Fully available again."
        if let nextReset {
            let isToday = nextReset.timeIntervalSince(now) < 86_400
            let when = ReportText.format(nextReset, template: isToday ? "jmm" : "EEEjmm", locale: locale, timeZone: timeZone)
            body += isToday ? " Next reset at \(when)." : " Next reset \(when)."
        }
        return SparkNotice(
            title: "\(provider.segmentLabel) · \(window) reset", body: body, thread: provider.rawValue, ring: .reset, provider: provider
        )
    }

    static func status(_ statusName: String) -> SparkNotice {
        SparkNotice(
            title: "Claude · \(statusName)", body: "Claude Code is having problems right now. Details on status.claude.com.",
            thread: UsageProvider.claude.rawValue, provider: .claude
        )
    }

    static func disconnected() -> SparkNotice {
        SparkNotice(
            title: "Claude · Disconnected", body: "Spark lost Keychain access. Open Spark and click Reconnect.",
            thread: UsageProvider.claude.rawValue, provider: .claude
        )
    }

    static func appUpdate(version: String) -> SparkNotice {
        SparkNotice(title: "Spark \(version) is available", body: "Download it in Settings > About.", thread: appThread)
    }

    static func cliUpdate(latest: String, installed: String, command: String) -> SparkNotice {
        SparkNotice(
            title: "Claude Code \(latest) is available", body: "You have \(installed). Update with \(command).",
            thread: UsageProvider.claude.rawValue, provider: .claude
        )
    }

    static let test = SparkNotice(title: "Spark · Test", body: "Notifications work.", thread: appThread)
}
