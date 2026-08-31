import Foundation

/// A week or calendar month, whichever the report is currently showing.
enum ReportPeriod: String, CaseIterable {
    case week = "Week"
    case month = "Month"
}

extension ReportPeriod: SegmentLabeled {
    var segmentLabel: String { rawValue }
}

/// A current-vs-previous-period token summary, navigable back one period at a time via
/// `periodOffset` (0 = the period containing "now"). The headline totals, trend, and cache hit
/// rate come from the same persisted `DailyRollup` data the Volume chart uses (see
/// `VolumeDaySeries` for the shared "window ends yesterday unless today already has a rollup"
/// convention this reuses); `modelTotals` and `topProjects` are supplied by the caller from a
/// live scan aligned to the same window via `windowStart`/`windowEnd`, since per-model/per-project
/// attribution isn't part of the permanent rollup.
struct PeriodReport {
    let currentPeriodTokens: Int
    let previousPeriodTokens: Int
    /// Percent change of `currentPeriodTokens` vs. `previousPeriodTokens`. `nil` when the
    /// previous period has no measurable tokens — no rollups at all, or rollups that sum to
    /// zero — since a percentage against zero would be meaningless.
    let trendPercent: Double?
    /// Fraction of prompt-cache-eligible tokens that were served from cache in the current
    /// period (`cacheRead / (cacheRead + cacheCreation)`). `nil` when there's no cache activity
    /// at all — a rate against zero would be meaningless.
    let cacheHitRate: Double?
    /// Total tokens per raw model ID, current period only. Real tokens (cache reads excluded),
    /// matching `currentPeriodTokens`.
    let modelTotals: [String: Int]
    let topProjects: [ProjectUsage]
    let period: ReportPeriod
    /// 0 = the current period; 1 = one period back, etc. — echoes the `periodOffset` this report
    /// was built for, so the view can label the shown range without recomputing boundaries.
    let periodOffset: Int
    /// The shown window's first and last calendar day.
    let rangeStart: Date
    let rangeEnd: Date

    var hasData: Bool {
        currentPeriodTokens > 0 || previousPeriodTokens > 0 || !topProjects.isEmpty
    }

    /// True only for the current month, on a day early enough that it hasn't closed yet (so
    /// `rangeEnd` lands before `rangeStart` — see `monthRange`). The trend/model split would
    /// otherwise read as "0 tokens, down 100%" against a live scan that still shows today's
    /// real activity.
    var isEmptyWindow: Bool { rangeEnd < rangeStart }

    static func build(
        rollups: [String: DailyRollup],
        modelTotals: [String: Int] = [:],
        topProjects: [ProjectUsage] = [],
        period: ReportPeriod = .week,
        periodOffset: Int = 0,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PeriodReport {
        let range = periodRange(period: period, offset: periodOffset, rollups: rollups, now: now, calendar: calendar)
        let previousRange = periodRange(period: period, offset: periodOffset + 1, rollups: rollups, now: now, calendar: calendar)

        let current = sum(rollups: rollups, start: range.start, end: range.end, calendar: calendar)
        let previous = sum(rollups: rollups, start: previousRange.start, end: previousRange.end, calendar: calendar)

        let trendPercent: Double? = previous.real > 0
            ? (Double(current.real - previous.real) / Double(previous.real)) * 100
            : nil
        let cacheEligible = current.cacheRead + current.cacheCreation
        let cacheHitRate: Double? = cacheEligible > 0 ? Double(current.cacheRead) / Double(cacheEligible) : nil

        return PeriodReport(
            currentPeriodTokens: current.real,
            previousPeriodTokens: previous.real,
            trendPercent: trendPercent,
            cacheHitRate: cacheHitRate,
            modelTotals: modelTotals,
            topProjects: topProjects,
            period: period,
            periodOffset: periodOffset,
            rangeStart: range.start,
            rangeEnd: range.end
        )
    }

    /// The shown window's first day — for a live scan (top projects, per-model split) that needs
    /// a lower cutoff aligned to the same window `build` sums rollups over.
    static func windowStart(
        period: ReportPeriod = .week,
        periodOffset: Int = 0,
        rollups: [String: DailyRollup],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        periodRange(period: period, offset: periodOffset, rollups: rollups, now: now, calendar: calendar).start
    }

    /// The upper bound a live scan must respect so a past period doesn't also pick up a later
    /// one's activity. `nil` for the current period (`periodOffset == 0`), where the scan should
    /// run through the present moment rather than stop at a fixed day.
    static func windowEnd(
        period: ReportPeriod = .week,
        periodOffset: Int = 0,
        rollups: [String: DailyRollup],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        guard periodOffset > 0 else { return nil }
        return periodRange(period: period, offset: periodOffset, rollups: rollups, now: now, calendar: calendar).end
    }

    /// Whether any rollup predates the shown window's first day — used to disable further "go
    /// back" navigation once there's nothing earlier to show. Checks the earliest rollup in all
    /// of history, not just the immediately preceding period: a single idle period (no activity,
    /// so no rollup for any of its days) must not be mistaken for the end of history and
    /// permanently block navigating past it.
    static func hasEarlierPeriod(
        period: ReportPeriod = .week,
        periodOffset: Int,
        rollups: [String: DailyRollup],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let earliestRollupDay = rollups.keys.min() else { return false }
        let shownStart = periodRange(period: period, offset: periodOffset, rollups: rollups, now: now, calendar: calendar).start
        return earliestRollupDay < TranscriptCache.dayKey(for: shownStart, calendar: calendar)
    }

    // MARK: - Period ranges

    private static func periodRange(
        period: ReportPeriod,
        offset: Int,
        rollups: [String: DailyRollup],
        now: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        switch period {
        case .week:
            let last = weekLastDay(rollups: rollups, weekOffset: offset, now: now, calendar: calendar)
            let start = calendar.date(byAdding: .day, value: -6, to: last) ?? last
            return (start, last)
        case .month:
            return monthRange(offset: offset, rollups: rollups, now: now, calendar: calendar)
        }
    }

    /// Only closed days are rolled up, so today would draw as an idle/zero day until it closes —
    /// the current week's (`weekOffset == 0`) window ends on the last day that can carry data
    /// instead. Earlier weeks are always fully closed, so they simply shift back by whole weeks.
    private static func weekLastDay(rollups: [String: DailyRollup], weekOffset: Int, now: Date, calendar: Calendar) -> Date {
        let todayKey = TranscriptCache.dayKey(for: now, calendar: calendar)
        let currentWeekLastDay = rollups[todayKey] == nil
            ? calendar.date(byAdding: .day, value: -1, to: now) ?? now
            : now
        guard weekOffset > 0 else { return currentWeekLastDay }
        return calendar.date(byAdding: .day, value: -(7 * weekOffset), to: currentWeekLastDay) ?? currentWeekLastDay
    }

    /// A full calendar month for any past month; for the current month (`offset == 0`), ends on
    /// the same "yesterday unless today is closed" day the week window uses. If today is the
    /// 1st and not yet closed, `end` lands one day before `start` — `sum` reads that as "nothing
    /// yet", not an error.
    private static func monthRange(offset: Int, rollups: [String: DailyRollup], now: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        guard let shownMonthStart = calendar.date(byAdding: .month, value: -offset, to: currentMonthStart) else {
            return (currentMonthStart, now)
        }

        guard offset > 0 else {
            let todayKey = TranscriptCache.dayKey(for: now, calendar: calendar)
            let end = rollups[todayKey] == nil ? (calendar.date(byAdding: .day, value: -1, to: now) ?? now) : now
            return (shownMonthStart, end)
        }

        guard let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: shownMonthStart),
              let lastDayOfMonth = calendar.date(byAdding: .day, value: -1, to: nextMonthStart) else {
            return (shownMonthStart, shownMonthStart)
        }
        return (shownMonthStart, lastDayOfMonth)
    }

    // MARK: - Summing rollups over a date range

    private struct PeriodTotals {
        var real = 0
        var cacheRead = 0
        var cacheCreation = 0
    }

    private static func sum(rollups: [String: DailyRollup], start: Date, end: Date, calendar: Calendar) -> PeriodTotals {
        guard start <= end else { return PeriodTotals() }
        var totals = PeriodTotals()
        var day = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        while day <= endDay {
            if let rollup = rollups[TranscriptCache.dayKey(for: day, calendar: calendar)] {
                totals.real += rollup.real
                totals.cacheRead += rollup.cacheRead
                totals.cacheCreation += rollup.cacheCreation
            }
            // Re-normalized via `startOfDay`, not used as-is: `date(byAdding:)` preserves
            // wall-clock time, so accumulating the raw result across a DST transition drifts
            // off midnight and the `day <= endDay` guard then terminates one day early,
            // silently dropping the period's last day.
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }
        return totals
    }
}
