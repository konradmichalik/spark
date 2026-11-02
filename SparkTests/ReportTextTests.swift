import XCTest
@testable import Spark

final class ReportTextTests: XCTestCase {
    private let locale = Locale(identifier: "en_GB")
    private let utc = TimeZone(identifier: "UTC") ?? .current

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }

    private func day(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day)) ?? .distantPast
    }

    func testMonthTitleNamesMonthAndYear() {
        let title = ReportText.periodTitle(.month, start: day(10, 1), end: day(10, 7), locale: locale, timeZone: utc)
        XCTAssertEqual(title, "October 2026")
    }

    func testWeekTitleNamesFirstAndLastDay() {
        let title = ReportText.periodTitle(.week, start: day(10, 5), end: day(10, 11), locale: locale, timeZone: utc)
        XCTAssertEqual(title, "5 Oct \u{2013} 11 Oct")
    }

    func testDailyAverageNeedsTwoActiveDays() {
        XCTAssertEqual(ReportText.dailyAverage(total: 5_000_000, activeDays: 4), "Average 1.2M tokens per active day")
        XCTAssertNil(ReportText.dailyAverage(total: 5_000_000, activeDays: 1))
        XCTAssertNil(ReportText.dailyAverage(total: 0, activeDays: 4))
    }
}
