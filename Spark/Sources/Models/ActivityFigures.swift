import Foundation

/// The key figures beside the activity calendar. Days after today are not part of any of them.
struct ActivityFigures: Equatable {
    let activeDays: Int
    let totalDays: Int
    let longestStreak: Int
    /// The day with the most fresh tokens, the latest one on a tie. `nil` without any use.
    let busiest: ActivityCell?

    /// `cells` in calendar order, as `ActivityCalendar.rows` returns them flattened.
    init(cells: [ActivityCell]) {
        let days = cells.filter(\.isDrawn)
        activeDays = days.filter { $0.tokens > 0 }.count
        totalDays = days.count
        busiest = days.filter { $0.tokens > 0 }.max { $0.tokens != $1.tokens ? $0.tokens < $1.tokens : $0.date < $1.date }
        var longest = 0
        var run = 0
        for day in days {
            run = day.tokens > 0 ? run + 1 : 0
            longest = max(longest, run)
        }
        longestStreak = longest
    }

    static func streakUnit(_ days: Int) -> String { days == 1 ? "day" : "days" }
}
