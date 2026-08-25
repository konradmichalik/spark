import Foundation

/// One day's session/weekly pace, aggregated from the raw polled snapshots recorded that day.
/// `nil` on either field means no snapshot at all landed that day (app not running, Mac asleep) —
/// distinct from a real 0%, mirroring `VolumeDay`'s `hasRollup` vs. zero-tokens distinction.
struct PaceDay: Identifiable {
    let day: Date
    let sessionUtilization: Double?
    let weeklyUtilization: Double?
    var id: Date { day }

    /// Whether any snapshot landed this day — the single definition of "idle" every consumer
    /// (the graph's gap bands, the "not enough data" placeholder) should check against.
    var hasData: Bool { sessionUtilization != nil || weeklyUtilization != nil }
}

/// Turns raw polled `UsageSnapshot`s into a gapless one-point-per-day series — plotting every
/// raw sample over a week or month is too dense (session utilization alone resets every 5h,
/// producing many sawtooth cycles a day) to read as an at-a-glance trend.
enum PaceDaySeries {
    /// One point per calendar day from `start` through `end` (inclusive), using each day's peak
    /// utilization per metric — utilization only ever climbs within a reset window, so the peak
    /// is what actually mattered that day (how close to the 5h/weekly cap it got).
    static func build(
        snapshots: [UsageSnapshot],
        start: Date,
        end: Date,
        calendar: Calendar = .current
    ) -> [PaceDay] {
        guard start <= end else { return [] }

        var byDay: [String: [UsageSnapshot]] = [:]
        for snapshot in snapshots {
            byDay[TranscriptCache.dayKey(for: snapshot.timestamp, calendar: calendar), default: []].append(snapshot)
        }

        var days: [PaceDay] = []
        var day = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        while day <= endDay {
            let samples = byDay[TranscriptCache.dayKey(for: day, calendar: calendar)]
            days.append(PaceDay(
                day: day,
                sessionUtilization: samples?.map(\.sessionUtilization).max(),
                weeklyUtilization: samples?.map(\.weeklyUtilization).max()
            ))
            // Re-normalized via `startOfDay`, not used as-is — `date(byAdding:)` preserves
            // wall-clock time, so accumulating the raw result across a DST transition drifts the
            // cursor off midnight and the `day <= endDay` guard then terminates one day early.
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }
        return days
    }
}
