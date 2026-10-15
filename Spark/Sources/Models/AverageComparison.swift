import Foundation

/// How a figure compares with the usual one (docs/design/rules.md, "Averages"). Neutral: more
/// use is neither good nor bad, so there is no colour and no verdict, only the size.
enum AverageComparison {
    /// Fewer days of use than this and an average is noise, so nothing is compared.
    static let minimumActiveDays = 5
    /// A day this far from the average, a fifth, is worth a note. Closer ones are left alone, or
    /// every day would carry one.
    static let notableShare = 0.2
    /// How many days back the typical day is taken from.
    static let typicalDayWindow = 28

    /// The median, not the mean, of the closed days with use before `today`, so one huge day does
    /// not make the rest look small. `nil` below `minimumActiveDays`.
    static func typicalDay(rollups: [String: DailyRollup], before today: Date, calendar: Calendar = .current) -> Int? {
        let start = calendar.startOfDay(for: today)
        let tokens = (1...typicalDayWindow).compactMap { offset -> Int? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: start) else { return nil }
            let real = rollups[TranscriptCache.dayKey(for: day, calendar: calendar)]?.real ?? 0
            return real > 0 ? real : nil
        }.sorted()
        guard tokens.count >= minimumActiveDays else { return nil }
        let middle = tokens.count / 2
        return tokens.count.isMultiple(of: 2) ? (tokens[middle - 1] + tokens[middle]) / 2 : tokens[middle]
    }

    /// The line under today's tokens and the sentence its tooltip adds. `nil` without use today or
    /// without enough earlier days to know what a typical one is.
    static func todayHint(
        tokens: Int, rollups: [String: DailyRollup], now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current
    ) -> (text: String, tooltip: String)? {
        guard tokens > 0, let typical = typicalDay(rollups: rollups, before: now, calendar: calendar) else { return nil }
        return (todayText(tokens: tokens, typical: typical, locale: locale), typicalDayTooltip(typical: typical))
    }

    /// Today is not over, so it is shown as a share of a typical day, not as above or below one.
    static func todayText(tokens: Int, typical: Int, locale: Locale = .current) -> String {
        "\(UsageFormat.percent(Double(tokens) / Double(max(typical, 1)) * 100, locale: locale)) of a typical day"
    }

    static func typicalDayTooltip(typical: Int) -> String {
        "A typical day is \(formatTokenCount(typical)) tokens: the median of the days you used it in the last "
            + "\(typicalDayWindow) days. Today is not over yet."
    }

    /// A finished day set against the daily average of its range: "1.4× the daily average" or
    /// "60% of the daily average". `nil` for a day close to the average.
    static func dayNote(tokens: Int, average: Int, locale: Locale = .current) -> String? {
        guard average > 0 else { return nil }
        let ratio = Double(tokens) / Double(average)
        if ratio >= 1 + notableShare {
            let multiple = ratio.formatted(.number.precision(.fractionLength(1)).locale(locale))
            return "\(multiple)\u{00D7} the daily average"
        }
        if ratio <= 1 - notableShare {
            return "\(UsageFormat.percent(ratio * 100, locale: locale)) of the daily average"
        }
        return nil
    }
}
