import Foundation

/// One day of the report's activity calendar, or a padding cell that only keeps the weekday columns aligned.
struct ActivityCell: Equatable {
    let date: Date
    let key: String
    let tokens: Int
    /// 0 for no use, then 1 to 3 relative to the busiest day of the period.
    let level: Int
    let isToday: Bool
    let isFuture: Bool
    let isOutsideRange: Bool

    var isDrawn: Bool { !isOutsideRange && !isFuture }
}

/// Lays a period out as weeks in rows and weekdays in columns (docs/design/rules.md, "Dot language").
enum ActivityCalendar {
    static let levelCount = 4

    static func rows(start: Date, end: Date, today: Date, dayTokens: [String: Int], calendar: Calendar) -> [[ActivityCell]] {
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        guard first <= last else { return [] }
        let todayStart = calendar.startOfDay(for: today)
        let days = daysBetween(first, last, calendar: calendar)
        let peak = days.map { dayTokens[TranscriptCache.dayKey(for: $0, calendar: calendar)] ?? 0 }.max() ?? 0

        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let trailing = (7 - (leading + days.count) % 7) % 7
        let cells = pad(leading, before: first, calendar: calendar)
            + days.map { cell(for: $0, today: todayStart, peak: peak, dayTokens: dayTokens, calendar: calendar) }
            + pad(trailing, after: last, calendar: calendar)
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
    }

    static func level(tokens: Int, peak: Int) -> Int {
        guard tokens > 0, peak > 0 else { return 0 }
        let share = Double(tokens) / Double(peak)
        return share <= 1.0 / 3 ? 1 : share <= 2.0 / 3 ? 2 : 3
    }

    /// Weekday initials in the calendar's column order.
    static func weekdayInitials(calendar: Calendar, locale: Locale = .current) -> [String] {
        var localized = calendar
        localized.locale = locale
        let symbols = localized.veryShortWeekdaySymbols
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }

    static func tooltipTitle(_ cell: ActivityCell, calendar: Calendar, locale: Locale = .current) -> String {
        dateText(cell.date, calendar: calendar, locale: locale)
    }

    static func tooltipBody(_ cell: ActivityCell) -> String {
        cell.tokens > 0 ? "\(formatTokenCount(cell.tokens)) tokens" : "No use"
    }

    /// The calendar in words for VoiceOver: how many days had use and which was the busiest.
    static func summary(_ figures: ActivityFigures, calendar: Calendar, locale: Locale = .current) -> String {
        guard let busiest = figures.busiest else { return "No use in this period" }
        let busiestText = "\(dateText(busiest.date, calendar: calendar, locale: locale)) with \(formatTokenCount(busiest.tokens)) tokens"
        return "Used on \(figures.activeDays) of \(figures.totalDays) days, busiest day \(busiestText)"
    }

    private static func dateText(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        ReportText.format(date, template: "EEEdMMM", locale: locale, timeZone: calendar.timeZone)
    }

    private static func cell(for day: Date, today: Date, peak: Int, dayTokens: [String: Int], calendar: Calendar) -> ActivityCell {
        let key = TranscriptCache.dayKey(for: day, calendar: calendar)
        let tokens = dayTokens[key] ?? 0
        return ActivityCell(
            date: day, key: key, tokens: tokens, level: level(tokens: tokens, peak: peak),
            isToday: day == today, isFuture: day > today, isOutsideRange: false
        )
    }

    private static func pad(_ count: Int, before first: Date, calendar: Calendar) -> [ActivityCell] {
        (1...max(count, 1)).reversed().prefix(count).compactMap { calendar.date(byAdding: .day, value: -$0, to: first) }.map(padding)
    }

    private static func pad(_ count: Int, after last: Date, calendar: Calendar) -> [ActivityCell] {
        (1...max(count, 1)).prefix(count).compactMap { calendar.date(byAdding: .day, value: $0, to: last) }.map(padding)
    }

    private static func padding(_ date: Date) -> ActivityCell {
        ActivityCell(date: date, key: "", tokens: 0, level: 0, isToday: false, isFuture: false, isOutsideRange: true)
    }

    /// Each day is re-normalized to midnight: `date(byAdding:)` keeps the wall-clock time, which
    /// drifts across a DST change (see `PeriodReport.sum`).
    private static func daysBetween(_ first: Date, _ last: Date, calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var day = first
        while day <= last {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }
        return days
    }
}
