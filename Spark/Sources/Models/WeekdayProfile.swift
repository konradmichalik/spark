import Foundation

/// The average fresh tokens on each weekday over a period, idle days counted as zero, so it shows
/// how use runs through the week.
struct WeekdayProfile: Equatable {
    struct Entry: Equatable {
        let name: String
        let fullName: String
        let average: Int
        /// How many of this weekday the period holds.
        let occurrences: Int
        /// The average as a percent of the busiest weekday's, the length of its dot bar.
        let share: Double

        var tooltip: String {
            "Average \(formatTokenCount(average)) tokens, from \(occurrences) days"
        }
    }

    /// Shorter than two weeks, a weekday has one or two samples and the profile would be chance.
    static let minimumDays = 14

    /// In the calendar's weekday order.
    let entries: [Entry]

    /// `nil` for a period shorter than `minimumDays` or without any use.
    static func make(
        dayTokens: [String: Int], start: Date, end: Date, calendar: Calendar = .current, locale: Locale = .current
    ) -> WeekdayProfile? {
        var sums = [Int: Int]()
        var counts = [Int: Int]()
        for day in ActivityCalendar.daysBetween(calendar.startOfDay(for: start), calendar.startOfDay(for: end), calendar: calendar) {
            let weekday = calendar.component(.weekday, from: day)
            sums[weekday, default: 0] += dayTokens[TranscriptCache.dayKey(for: day, calendar: calendar)] ?? 0
            counts[weekday, default: 0] += 1
        }
        guard counts.values.reduce(0, +) >= minimumDays else { return nil }

        var localized = calendar
        localized.locale = locale
        let averages = (1...7).map { (sums[$0] ?? 0) / max(counts[$0] ?? 1, 1) }
        guard let busiest = averages.max(), busiest > 0 else { return nil }
        let entries = (0..<7).map { position -> Entry in
            let weekday = (calendar.firstWeekday - 1 + position) % 7 + 1
            let average = averages[weekday - 1]
            return Entry(
                name: localized.shortWeekdaySymbols[weekday - 1], fullName: localized.weekdaySymbols[weekday - 1],
                average: average, occurrences: counts[weekday] ?? 0, share: Double(average) / Double(busiest) * 100
            )
        }
        return WeekdayProfile(entries: entries)
    }
}
