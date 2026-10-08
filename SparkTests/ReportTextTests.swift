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

    func testComparisonNamesThePreviousMonth() {
        XCTAssertEqual(ReportText.comparisonLabel(.month, start: day(10, 1), locale: locale, timeZone: utc), "VS SEPTEMBER")
        XCTAssertEqual(ReportText.comparisonLabel(.month, start: day(1, 1), locale: locale, timeZone: utc), "VS DECEMBER")
    }

    func testComparisonForAWeek() {
        XCTAssertEqual(ReportText.comparisonLabel(.week, start: day(10, 5), locale: locale, timeZone: utc), "VS LAST WEEK")
    }

    func testTrendIsSignedAndRoundedWithTheUnitApart() {
        XCTAssertEqual(ReportText.trend(12.4), NumberParts(number: "+12", unit: "%"))
        XCTAssertEqual(ReportText.trend(-5.6), NumberParts(number: "-6", unit: "%"))
        XCTAssertEqual(ReportText.trend(0.3), NumberParts(number: "0", unit: "%"))
        XCTAssertNil(ReportText.trend(nil))
    }

    func testListsShowThreeAndExpandTheRest() {
        XCTAssertEqual(ShowMore(total: 5, limit: ReportText.listLimit).label(expanded: false), "Show 2 more")
        XCTAssertNil(ShowMore(total: 4, limit: ReportText.listLimit).label(expanded: false))
    }
}

final class PaceColumnsTests: XCTestCase {
    private let locale = Locale(identifier: "en_GB")
    private let utc = TimeZone(identifier: "UTC") ?? .current

    private func day(_ offset: Int) -> Date {
        // Monday, 5 October 2026, 00:00 UTC.
        Date(timeIntervalSince1970: 1_791_158_400 + Double(offset) * 86_400)
    }

    private var days: [PaceDay] {
        [
            PaceDay(day: day(0), sessionUtilization: 78, weeklyUtilization: 40),
            PaceDay(day: day(1), sessionUtilization: nil, weeklyUtilization: nil),
            PaceDay(day: day(2), sessionUtilization: nil, weeklyUtilization: nil),
            PaceDay(day: day(3), sessionUtilization: nil, weeklyUtilization: nil),
            PaceDay(day: day(4), sessionUtilization: 30, weeklyUtilization: 52)
        ]
    }

    func testOneColumnPerDayWithItsPeaks() {
        let columns = PaceColumns.make(days)
        XCTAssertEqual(columns.count, 5)
        XCTAssertEqual(columns[0], HistoryColumn(session: 78, weekly: 40, slotStart: day(0)))
        XCTAssertFalse(columns[1].hasValue)
    }

    func testHoverReadsTheDayAndBothPeaks() throws {
        let text = try XCTUnwrap(PaceColumns.hover(.column(0), in: days, locale: locale, timeZone: utc))
        XCTAssertEqual(text.title, "Mon 5 Oct")
        XCTAssertEqual(text.body, "Session peak 78%\nWeek 40%")
    }

    func testHoverOverAGapNamesItsDays() throws {
        let text = try XCTUnwrap(PaceColumns.hover(.gap(1..<4), in: days, locale: locale, timeZone: utc))
        XCTAssertEqual(text.title, "Tue 6 Oct \u{2013} Thu 8 Oct")
        XCTAssertEqual(text.body, "No data here. The Mac may have slept, or Spark was closed or polling slowly")
    }

    func testAxisLabelsAreDays() {
        let columns = PaceColumns.make(days)
        let labels = HistoryAxis.labels(
            items: HistoryLayout.items(columns), columns: columns, locale: locale, timeZone: utc, includesDate: true
        )
        XCTAssertEqual(labels, ["5 Oct", "6 Oct", "9 Oct"])
    }
}

final class ModelRowOrderTests: XCTestCase {
    func testRowsComeLargestFirst() {
        let rows = ModelRow.rows(from: ["claude-sonnet-5-5": 10, "claude-opus-5-5": 400, "claude-fable-1": 50])
        XCTAssertEqual(rows.map(\.label), ["Opus", "Fable", "Sonnet"])
    }
}
