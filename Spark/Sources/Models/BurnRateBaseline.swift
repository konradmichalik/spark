import Foundation

/// What a normal burn rate is for this user: the median and 90th percentile of the active
/// 15-minute windows of the last 14 days. The tiers and the gauge are read against it.
struct BurnRateBaseline: Equatable, Sendable {
    static let span: TimeInterval = 14 * 24 * 60 * 60
    /// Fewer completed windows say too little about a user, so the fixed thresholds apply.
    static let minimumWindows = 20

    /// Roughly the median and the 90th percentile of active windows across two weeks of one
    /// person's transcripts.
    static let fallback = BurnRateBaseline(median: 20_000, p90: 60_000, rates: [])

    let median: Int
    let p90: Int
    /// Ascending, tokens per minute. Empty for the fallback.
    let rates: [Int]

    static func windowIndex(of date: Date) -> Int {
        Int(date.timeIntervalSince1970 / BurnRate.window)
    }

    /// `windowTokens` maps a window index to its fresh tokens. The window still filling and
    /// idle windows are left out, so a rate is never compared with an unfinished sample.
    static func calculate(windowTokens: [Int: Int], now: Date) -> BurnRateBaseline {
        let current = windowIndex(of: now)
        let oldest = windowIndex(of: now.addingTimeInterval(-span))
        let minutes = Int(BurnRate.window / 60)
        let rates = windowTokens
            .filter { $0.key >= oldest && $0.key < current && $0.value > 0 }
            .map { Int((Double($0.value) / Double(minutes)).rounded()) }
            .sorted()
        guard rates.count >= minimumWindows else { return .fallback }
        return BurnRateBaseline(median: nearestRank(0.5, in: rates), p90: nearestRank(0.9, in: rates), rates: rates)
    }

    static func windowTokens(of turns: [TurnSample]) -> [Int: Int] {
        turns.reduce(into: [:]) { $0[windowIndex(of: $1.date), default: 0] += $1.tokens }
    }

    /// Applied at parse time so a file's windows never outgrow the span they are read over.
    static func pruned(_ windowTokens: [Int: Int], now: Date = Date()) -> [Int: Int] {
        let oldest = windowIndex(of: now.addingTimeInterval(-span))
        return windowTokens.filter { $0.key >= oldest }
    }

    /// The share of windows below `rate`, in `0...100`. `nil` without a measured baseline.
    func percent(of rate: Int) -> Int? {
        guard !rates.isEmpty else { return nil }
        let below = rates.filter { $0 < rate }.count
        return Int((Double(below) / Double(rates.count) * 100).rounded())
    }

    private static func nearestRank(_ fraction: Double, in sorted: [Int]) -> Int {
        sorted[max(Int((fraction * Double(sorted.count)).rounded(.up)) - 1, 0)]
    }
}
