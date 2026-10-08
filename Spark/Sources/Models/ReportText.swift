import Foundation

/// The words and numbers of the usage report window (board 11).
enum ReportText {
    /// Entries a report list shows before "Show N more".
    static let listLimit = 3

    /// "October 2026", or "5 Oct – 11 Oct" for a week.
    static func periodTitle(
        _ period: ReportPeriod, start: Date, end: Date, locale: Locale = .current, timeZone: TimeZone = .current
    ) -> String {
        switch period {
        case .month:
            return format(start, template: "MMMMyyyy", locale: locale, timeZone: timeZone)
        case .week:
            let day = { format($0, template: "dMMM", locale: locale, timeZone: timeZone) }
            return "\(day(start)) \u{2013} \(day(end))"
        }
    }

    /// The micro label over the change tile: the previous month by name, or the previous week.
    static func comparisonLabel(
        _ period: ReportPeriod, start: Date, locale: Locale = .current, timeZone: TimeZone = .current
    ) -> String {
        switch period {
        case .week:
            return "VS LAST WEEK"
        case .month:
            let previous = start.addingTimeInterval(-86_400)
            return "VS \(format(previous, template: "MMMM", locale: locale, timeZone: timeZone).uppercased(with: locale))"
        }
    }

    /// The change against the previous period, signed and rounded, the unit apart for Doto.
    static func trend(_ percent: Double?) -> NumberParts? {
        guard let percent, percent.isFinite else { return nil }
        let rounded = Int(percent.rounded())
        return NumberParts(number: rounded > 0 ? "+\(rounded)" : "\(rounded)", unit: "%")
    }

    static func format(_ date: Date, template: String, locale: Locale, timeZone: TimeZone) -> String {
        HistoryAxis.formatter(locale: locale, timeZone: timeZone, template: template).string(from: date)
    }
}

/// The pace graph of the report as dot columns: one column per day with the day's peak session,
/// the week's peak as the line (docs/design/rules.md, "Dot language").
enum PaceColumns {
    static func make(_ days: [PaceDay]) -> [HistoryColumn] {
        days.map { HistoryColumn(session: $0.sessionUtilization, weekly: $0.weeklyUtilization, slotStart: $0.day) }
    }

    static func hover(
        _ item: HistoryItem, in days: [PaceDay], locale: Locale = .current, timeZone: TimeZone = .current
    ) -> (title: String, body: String)? {
        let dayName = { ReportText.format($0, template: "EEEdMMM", locale: locale, timeZone: timeZone) }
        switch item {
        case .column(let index):
            guard let day = days[safe: index], day.hasData else { return nil }
            let lines = [
                day.sessionUtilization.map { "Session peak \(UsageFormat.percent($0, locale: locale))" },
                day.weeklyUtilization.map { "Week \(UsageFormat.percent($0, locale: locale))" }
            ]
            return (dayName(day.day), lines.compactMap { $0 }.joined(separator: "\n"))
        case .gap(let range):
            guard let first = days[safe: range.lowerBound], let last = days[safe: range.upperBound - 1] else { return nil }
            return ("\(dayName(first.day)) \u{2013} \(dayName(last.day))", "No data. The Mac was asleep or Spark was closed")
        }
    }
}
