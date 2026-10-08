@testable import Spark
import XCTest

/// The Berlin Gregorian calendar the date based tests share, so day boundaries and DST are the
/// same everywhere.
enum TestCalendar {
    static func berlin(firstWeekday: Int? = nil) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        if let firstWeekday { calendar.firstWeekday = firstWeekday }
        return calendar
    }

    /// `day` is `yyyy-MM-dd`; the time defaults to noon so no DST shift moves it to another day.
    static func date(_ day: String, time: String = "12:00", calendar: Calendar = berlin()) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "\(day) \(time)") ?? Date(timeIntervalSince1970: 0)
    }
}

extension ActivityCell {
    /// The cell's day key in the shared calendar, for assertions on which day a cell is.
    var dayKey: String { TranscriptCache.dayKey(for: date, calendar: TestCalendar.berlin()) }
}
