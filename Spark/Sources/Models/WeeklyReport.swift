import Foundation

/// A rolling current-week vs. previous-week token summary. The headline totals and trend come
/// from the same persisted `DailyRollup` data the Volume chart uses (see `VolumeDaySeries` for
/// the shared "window ends yesterday unless today already has a rollup" convention this reuses);
/// `modelTotals` and `topProjects` are supplied by the caller from a live scan aligned to the
/// same window via `windowStart`, since per-model/per-project attribution isn't part of the
/// permanent rollup.
struct WeeklyReport {
    private static let daysPerWindow = 7

    let currentWeekTokens: Int
    let previousWeekTokens: Int
    /// Percent change of `currentWeekTokens` vs. `previousWeekTokens`. `nil` when the previous
    /// week has no measurable tokens — no rollups at all, or rollups that sum to zero — since a
    /// percentage against zero would be meaningless.
    let trendPercent: Double?
    /// Total tokens per raw model ID, current week only. Real tokens (cache reads excluded),
    /// matching `currentWeekTokens`.
    let modelTotals: [String: Int]
    let topProjects: [ProjectUsage]

    var hasData: Bool {
        currentWeekTokens > 0 || previousWeekTokens > 0 || !topProjects.isEmpty
    }

    static func build(
        rollups: [String: DailyRollup],
        modelTotals: [String: Int] = [:],
        topProjects: [ProjectUsage] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyReport {
        let lastDay = self.lastDay(rollups: rollups, now: now, calendar: calendar)

        let currentTokens = sum(rollups: rollups, daysBack: 0..<daysPerWindow, endingAt: lastDay, calendar: calendar)
        let previousTokens = sum(
            rollups: rollups,
            daysBack: daysPerWindow..<(daysPerWindow * 2),
            endingAt: lastDay,
            calendar: calendar
        )

        let trendPercent: Double? = previousTokens > 0
            ? (Double(currentTokens - previousTokens) / Double(previousTokens)) * 100
            : nil

        return WeeklyReport(
            currentWeekTokens: currentTokens,
            previousWeekTokens: previousTokens,
            trendPercent: trendPercent,
            modelTotals: modelTotals,
            topProjects: topProjects
        )
    }

    /// The first calendar day of the current window — for a live scan (top projects, per-model
    /// split) that needs a cutoff aligned to the same window `build` sums rollups over.
    static func windowStart(rollups: [String: DailyRollup], now: Date = Date(), calendar: Calendar = .current) -> Date {
        let lastDay = self.lastDay(rollups: rollups, now: now, calendar: calendar)
        return calendar.date(byAdding: .day, value: -(daysPerWindow - 1), to: lastDay) ?? lastDay
    }

    /// Only closed days are rolled up, so today would draw as an idle/zero day until it closes —
    /// the window ends on the last day that can carry data instead.
    private static func lastDay(rollups: [String: DailyRollup], now: Date, calendar: Calendar) -> Date {
        let todayKey = TranscriptCache.dayKey(for: now, calendar: calendar)
        return rollups[todayKey] == nil
            ? calendar.date(byAdding: .day, value: -1, to: now) ?? now
            : now
    }

    private static func sum(
        rollups: [String: DailyRollup],
        daysBack range: Range<Int>,
        endingAt lastDay: Date,
        calendar: Calendar
    ) -> Int {
        range.reduce(0) { total, offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: lastDay),
                  let rollup = rollups[TranscriptCache.dayKey(for: date, calendar: calendar)] else { return total }
            return total + rollup.real
        }
    }
}
