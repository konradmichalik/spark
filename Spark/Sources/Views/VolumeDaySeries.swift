import Foundation

/// One lane of the Volume chart: a calendar day inside the visible window, with its token total.
/// `tokens == 0` means the day is inside the window but has no rollup at all.
struct VolumeDay: Identifiable {
    let day: String
    let tokens: Int

    var isEmpty: Bool { tokens == 0 }
    var id: String { day }
}

/// Turns the sparse rollup dictionary into a gapless day series.
///
/// Plotting only the days that carry rollups makes the chart re-flow every time a day drops out
/// of the window or a new one lands: bar widths and axis labels shift under the pointer. Emitting
/// every calendar day in the range instead keeps each lane in place, and idle days read as idle,
/// the same way the Limits graph marks stretches with no data instead of dropping them.
enum VolumeDaySeries {
    static func build(
        rollups: [String: DailyRollup],
        timeRange: GraphTimeRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [VolumeDay] {
        // Only closed days are rolled up (see `DailyRollup.merging`), so today would draw as an
        // idle lane for the whole day. The window ends on the last day that can carry data.
        let todayKey = TranscriptCache.dayKey(for: now, calendar: calendar)
        let lastDay = rollups[todayKey] == nil
            ? calendar.date(byAdding: .day, value: -1, to: now) ?? now
            : now

        let dayCount = max(1, Int(timeRange.seconds / 86_400))
        return (0..<dayCount).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: lastDay) else { return nil }
            let key = TranscriptCache.dayKey(for: date, calendar: calendar)
            return VolumeDay(day: key, tokens: rollups[key]?.totalTokens ?? 0)
        }
    }
}
