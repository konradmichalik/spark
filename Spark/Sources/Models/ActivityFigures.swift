import Foundation

/// The report's activity figures. Days after today are not part of any of them.
struct ActivityFigures: Equatable {
    let activeDays: Int
    let totalDays: Int
    let longestStreak: Int
    /// The day with the most fresh tokens, the latest one on a tie. `nil` without any use.
    let busiest: ReportDay?

    /// `days` in calendar order.
    init(days: [ReportDay]) {
        let counted = days.filter { !$0.isFuture }
        activeDays = counted.filter { $0.total > 0 }.count
        totalDays = counted.count
        busiest = counted.filter { $0.total > 0 }.max { $0.total != $1.total ? $0.total < $1.total : $0.date < $1.date }
        var longest = 0
        var run = 0
        for day in counted {
            run = day.total > 0 ? run + 1 : 0
            longest = max(longest, run)
        }
        longestStreak = longest
    }

    static func streakUnit(_ days: Int) -> String { days == 1 ? "day" : "days" }
}
