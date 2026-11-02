import Foundation

/// One calendar day of the usage report's Activity graph, split by provider.
struct ReportDay: Identifiable, Equatable, Sendable {
    let date: Date
    /// The day key as `TranscriptCache.dayKey` writes it.
    let key: String
    let claude: Int
    let codex: Int
    let isToday: Bool
    let isFuture: Bool
    /// The day against the range's daily average (docs/design/rules.md, "Averages"). `nil` for an
    /// idle day, a day not yet over and a day close to the average.
    let note: String?

    var total: Int { claude + codex }
    var id: String { key }
}

/// The report's days for a scope: one entry per calendar day of the range, the Activity figures
/// and the daily average the days are compared with.
struct ReportDaySeries: Equatable, Sendable {
    let days: [ReportDay]
    /// Days up to today with use.
    let activeDays: Int
    /// The days of the range up to today, what `activeDays` is counted against.
    let daysUpToToday: Int
    let longestStreak: Int
    /// The day with the most fresh tokens, the latest on a tie. `nil` without any use.
    let busiest: ReportDay?
    /// The mean of the finished days with use. `nil` below `AverageComparison.minimumActiveDays`.
    let dailyAverage: Int?

    /// `claude` and `codex` are fresh tokens per day key; the scope leaves out the provider it
    /// does not cover.
    static func make(
        claude: [String: Int], codex: [String: Int], scope: ReportScope, start: Date, end: Date,
        now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current
    ) -> ReportDaySeries {
        let today = calendar.startOfDay(for: now)
        let tokens = calendar.dayStarts(from: calendar.startOfDay(for: start), through: calendar.startOfDay(for: end))
            .map { date in
                let key = TranscriptCache.dayKey(for: date, calendar: calendar)
                return DayTokens(
                    date: date, key: key, claude: scope == .codex ? 0 : claude[key] ?? 0, codex: scope == .claude ? 0 : codex[key] ?? 0
                )
            }
        // Today is not over, so it neither shapes the average nor is compared with it.
        let average = AverageComparison.dailyAverage(activeDayTokens: tokens.filter { $0.date < today && $0.total > 0 }.map(\.total))
        let days = tokens.map { day in
            let isFinishedUse = day.date < today && day.total > 0
            return ReportDay(
                date: day.date, key: day.key, claude: day.claude, codex: day.codex,
                isToday: day.date == today, isFuture: day.date > today,
                note: isFinishedUse ? average.flatMap { AverageComparison.dayNote(tokens: day.total, average: $0, locale: locale) } : nil
            )
        }
        let figures = ActivityFigures(cells: days.map {
            ActivityCell(date: $0.date, tokens: $0.total, isToday: $0.isToday, isFuture: $0.isFuture)
        })
        return ReportDaySeries(
            days: days, activeDays: figures.activeDays, daysUpToToday: figures.totalDays, longestStreak: figures.longestStreak,
            busiest: figures.busiest.flatMap { busiest in days.first { $0.date == busiest.date } }, dailyAverage: average
        )
    }

    /// The days the columns show: a week's seven days, the current one ending today, or every day
    /// of the month, so the days still to come keep their place.
    static func range(for report: PeriodReport, calendar: Calendar = .current) -> (start: Date, end: Date) {
        guard report.period == .month,
              let month = calendar.dateInterval(of: .month, for: report.rangeStart),
              let last = calendar.date(byAdding: .day, value: -1, to: month.end) else {
            return (report.calendarStart, report.calendarEnd)
        }
        return (month.start, calendar.startOfDay(for: last))
    }

    private struct DayTokens {
        let date: Date
        let key: String
        let claude: Int
        let codex: Int

        var total: Int { claude + codex }
    }
}

extension Calendar {
    /// Every midnight from `first` through `last`. Each day is re-normalized to midnight:
    /// `date(byAdding:)` keeps the wall-clock time, which drifts across a DST change (see
    /// `PeriodReport.sum`).
    func dayStarts(from first: Date, through last: Date) -> [Date] {
        var days: [Date] = []
        var day = first
        while day <= last {
            days.append(day)
            guard let next = date(byAdding: .day, value: 1, to: day) else { break }
            day = startOfDay(for: next)
        }
        return days
    }
}
