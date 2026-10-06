import Foundation

/// One counted assistant turn: its timestamp and its fresh tokens (input, output and cache
/// writes, without cache reads — see `ModelTokenTotals.real`).
struct TurnSample: Codable, Equatable, Sendable {
    let date: Date
    let tokens: Int
}

/// Fresh tokens per minute across all sessions, averaged over the last `window`. Reacts to local
/// activity immediately, while the usage API's utilization only moves on the next poll.
struct BurnRate: Equatable, Sendable {
    enum Tier: Equatable, Sendable {
        case normal, moderate, high

        var label: String {
            switch self {
            case .normal: "Normal"
            case .moderate: "Moderate"
            case .high: "High"
            }
        }
    }

    static let window: TimeInterval = 15 * 60

    /// Roughly the median and the 90th percentile of active 15-minute windows across two weeks
    /// of real transcripts.
    private static let moderateThreshold = 20_000
    private static let highThreshold = 60_000

    let tokensPerMinute: Int

    var tier: Tier {
        if tokensPerMinute >= Self.highThreshold { return .high }
        if tokensPerMinute >= Self.moderateThreshold { return .moderate }
        return .normal
    }

    /// Divides by the full window rather than the span since the first turn, so a single turn
    /// right after a pause reads as a short burst instead of an extreme rate.
    static func calculate(files: [FileParseCache], now: Date = Date()) -> BurnRate? {
        let recent = files.flatMap(\.recentTurns).filter { isRecent($0, now: now) }
        guard !recent.isEmpty else { return nil }
        let tokens = recent.reduce(0) { $0 + $1.tokens }
        return BurnRate(tokensPerMinute: Int((Double(tokens) / (window / 60)).rounded()))
    }

    /// Applied at parse time, so idle files carry no samples. An unchanged file isn't reparsed,
    /// so its samples still age out in `calculate`.
    static func pruned(_ turns: [TurnSample], now: Date = Date()) -> [TurnSample] {
        turns.filter { isRecent($0, now: now) }
    }

    /// Future timestamps (clock skew, bad data) are dropped rather than counted until they age.
    private static func isRecent(_ turn: TurnSample, now: Date) -> Bool {
        let age = now.timeIntervalSince(turn.date)
        return age >= 0 && age <= window
    }
}
