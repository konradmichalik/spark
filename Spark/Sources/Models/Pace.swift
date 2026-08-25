import Foundation

/// Pace compares the consumed fraction of a quota against the elapsed fraction of its window —
/// stable during a pause (unlike `SessionProjection`'s linear extrapolation, which collapses to
/// "insufficient data" the moment there's no recent-usage delta to project from) and answering
/// the question a subscriber actually has: ahead of or behind budget, right now.
enum Pace {
    struct Result: Equatable, Sendable {
        /// `utilization / elapsedFraction`. Above 1.0 means the current average, held steady,
        /// exhausts the quota before the window resets.
        let ratio: Double
        /// How much of the window has elapsed, in `0...1`.
        let elapsedFraction: Double

        /// Six-tier classification of `ratio`, from comfortably under budget to badly overspending.
        var tier: Tier {
            switch ratio {
            case ..<0.5: .comfortable
            case ..<0.75: .onTrack
            case ..<0.9: .warming
            case ..<1.0: .pressing
            case ..<1.2: .critical
            default: .runaway
            }
        }
    }

    /// Where `ratio` falls, from comfortably under budget (`comfortable`) to badly overspending
    /// (`runaway`). Boundaries mirror projected end-of-window utilization: a `ratio` of 1.2 means
    /// the quota would be exhausted at 120% if the current rate held steady to reset.
    enum Tier: Sendable {
        case comfortable, onTrack, warming, pressing, critical, runaway

        var label: String {
            switch self {
            case .comfortable: "Comfortable"
            case .onTrack: "On Track"
            case .warming: "Warming"
            case .pressing: "Pressing"
            case .critical: "Critical"
            case .runaway: "Runaway"
            }
        }
    }

    /// The API returns only `resetsAt`, not a window start, so `windowLength` (the bucket's full
    /// duration — 5 hours or 7 days) is required to reconstruct it. Returns `nil` whenever the
    /// inputs can't support a trustworthy answer, rather than fabricating one: no `resetsAt`, a
    /// `resetsAt` already in the past, or one so far in the future it implies more of the window
    /// has "elapsed" than the window is long (a stale value past its own prior reset).
    static func calculate(
        utilization: Double,
        resetsAt: Date?,
        windowLength: TimeInterval,
        now: Date = Date()
    ) -> Result? {
        guard let resetsAt, windowLength > 0 else { return nil }

        let windowStart = resetsAt.addingTimeInterval(-windowLength)
        let elapsedFraction = now.timeIntervalSince(windowStart) / windowLength
        guard elapsedFraction > 0, elapsedFraction <= 1 else { return nil }

        return Result(ratio: (utilization / 100) / elapsedFraction, elapsedFraction: elapsedFraction)
    }
}
