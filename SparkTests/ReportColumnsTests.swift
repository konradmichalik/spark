@testable import Spark
import XCTest

final class ReportColumnLayoutTests: XCTestCase {
    func testRowsThatFitTheColumnHeights() {
        XCTAssertEqual(ReportColumnLayout.maxRows(height: 60), 10)
        XCTAssertEqual(ReportColumnLayout.maxRows(height: 156), 26)
        XCTAssertEqual(ReportColumnLayout.maxRows(height: 96), 16)
        XCTAssertEqual(ReportColumnLayout.maxRows(height: 2), 1)
    }

    func testBusiestDayFillsTheColumnAndAnyUseShowsOneDot() {
        XCTAssertEqual(ReportColumnLayout.rows(tokens: 500, peak: 500, maxRows: 26), 26)
        XCTAssertEqual(ReportColumnLayout.rows(tokens: 250, peak: 500, maxRows: 26), 13)
        XCTAssertEqual(ReportColumnLayout.rows(tokens: 1, peak: 500, maxRows: 26), 1)
        XCTAssertEqual(ReportColumnLayout.rows(tokens: 0, peak: 500, maxRows: 26), 0)
        XCTAssertEqual(ReportColumnLayout.rows(tokens: 10, peak: 0, maxRows: 26), 0)
    }

    func testStackSplitsTheColumnByProvider() {
        XCTAssertEqual(ReportColumnLayout.stack(claude: 300, codex: 100, peak: 400, maxRows: 10), ReportColumnStack(claude: 8, codex: 2))
        XCTAssertEqual(ReportColumnLayout.stack(claude: 0, codex: 200, peak: 400, maxRows: 10), ReportColumnStack(claude: 0, codex: 5))
        XCTAssertEqual(ReportColumnLayout.stack(claude: 0, codex: 0, peak: 400, maxRows: 10), ReportColumnStack(claude: 0, codex: 0))
    }

    func testStackKeepsADotForTheSmallerProvider() {
        let stack = ReportColumnLayout.stack(claude: 990, codex: 10, peak: 1000, maxRows: 10)

        XCTAssertEqual(stack, ReportColumnStack(claude: 9, codex: 1))
        XCTAssertEqual(stack.total, 10)
    }

    func testPercentColumnsReachTheTopAtTheLimit() {
        XCTAssertEqual(ReportColumnLayout.percentRows(100, maxRows: 16), 16)
        XCTAssertEqual(ReportColumnLayout.percentRows(50, maxRows: 16), 8)
        XCTAssertEqual(ReportColumnLayout.percentRows(140, maxRows: 16), 16)
        XCTAssertEqual(ReportColumnLayout.percentRows(0, maxRows: 16), 1)
        XCTAssertEqual(ReportColumnLayout.percentRows(nil, maxRows: 16), 0)
    }

    func testColumnCentresShareTheWidth() {
        XCTAssertEqual(ReportColumnLayout.centerX(index: 0, count: 4, width: 400), 50)
        XCTAssertEqual(ReportColumnLayout.centerX(index: 3, count: 4, width: 400), 350)
        XCTAssertEqual(ReportColumnLayout.centerX(index: 0, count: 0, width: 400), 0)
    }
}

final class ReportColumnMotionTests: XCTestCase {
    func testColumnsGrowLeftToRight() {
        let first = ReportColumnMotion.shown(from: 0, to: 10, index: 0, count: 7, progress: 0.2)
        let last = ReportColumnMotion.shown(from: 0, to: 10, index: 6, count: 7, progress: 0.2)

        XCTAssertGreaterThan(first, last)
        XCTAssertEqual(ReportColumnMotion.shown(from: 0, to: 10, index: 6, count: 7, progress: 0), 0)
    }

    func testTheLastColumnIsFullWhenTheFillEnds() {
        XCTAssertEqual(ReportColumnMotion.shown(from: 0, to: 10, index: 30, count: 31, progress: 0.999), 10)
        XCTAssertEqual(ReportColumnMotion.shown(from: 0, to: 10, index: 30, count: 31, progress: 1), 10)
    }

    func testStartsFollowTheDotBarSpacing() {
        XCTAssertEqual(ReportColumnMotion.start(index: 2, count: 7), 0.05, accuracy: 1e-9)
        // 31 columns must start within the first half of the fill, closer than 25 ms.
        XCTAssertEqual(ReportColumnMotion.start(index: 30, count: 31), 0.15, accuracy: 1e-9)
    }

    func testAFallShowsAtOnce() {
        XCTAssertEqual(ReportColumnMotion.shown(from: 8, to: 3, index: 0, count: 7, progress: 0), 3)
    }

    func testOnlyARiseStartsAFill() {
        XCTAssertEqual(ReportColumnMotion.starts(old: [3, 5], new: [4, 2]), [3, 2])
        XCTAssertNil(ReportColumnMotion.starts(old: [3, 5], new: [3, 1]))
        XCTAssertEqual(ReportColumnMotion.starts(old: [3], new: [4, 2]), [0, 0])
    }
}

final class ReportWeekLineTests: XCTestCase {
    func testADayWithoutAWeeklyValueBreaksTheLine() {
        let segments = ReportWeekLine.segments([10, 20, nil, 40, nil, nil, 60, 70])

        XCTAssertEqual(segments.map { $0.map(\.index) }, [[0, 1], [3], [6, 7]])
        XCTAssertEqual(segments.last?.map(\.value), [60, 70])
    }

    func testValuesAreClampedToTheGraph() {
        XCTAssertEqual(ReportWeekLine.segments([120, -5]).first?.map(\.value), [100, 0])
    }
}

final class ReportDayAxisTests: XCTestCase {
    private let calendar = TestCalendar.berlin()
    private let locale = Locale(identifier: "en_US")

    private func dates(from first: String, to last: String) -> [Date] {
        calendar.dayStarts(from: calendar.startOfDay(for: TestCalendar.date(first)), through: calendar.startOfDay(for: TestCalendar.date(last)))
    }

    func testAMonthIsLabelledEveryWeekFromTheFirst() {
        let labels = ReportDayAxis.labels(dates: dates(from: "2026-10-01", to: "2026-10-31"), period: .month, calendar: calendar, locale: locale)

        XCTAssertEqual(labels.map(\.index), [0, 7, 14, 21, 28])
        XCTAssertEqual(labels.map(\.text), ["1", "8", "15", "22", "29"])
    }

    func testAWeekLabelsEveryDayWithItsWeekday() {
        let labels = ReportDayAxis.labels(dates: dates(from: "2026-10-05", to: "2026-10-11"), period: .week, calendar: calendar, locale: locale)

        XCTAssertEqual(labels.map(\.index), Array(0..<7))
        XCTAssertEqual(labels.first?.text, "Mon 5")
        XCTAssertEqual(labels.last?.text, "Sun 11")
    }
}

final class ReportDayTextTests: XCTestCase {
    private let calendar = TestCalendar.berlin()
    private let locale = Locale(identifier: "en_US")

    private func day(claude: Int, codex: Int, note: String? = nil) -> ReportDay {
        ReportDay(
            date: TestCalendar.date("2026-10-14"), key: "2026-10-14", claude: claude, codex: codex,
            isToday: false, isFuture: false, note: note
        )
    }

    func testTooltipNamesTheTokensAndTheNote() {
        XCTAssertEqual(ReportDayText.body(day(claude: 1_200_000, codex: 0, note: "1.4\u{00D7} the daily average"), scope: .claude),
                       "1.2M tokens\n1.4\u{00D7} the daily average")
        XCTAssertEqual(ReportDayText.body(day(claude: 0, codex: 0), scope: .all), "No use")
    }

    func testTooltipSplitsTheProvidersInAll() {
        XCTAssertEqual(ReportDayText.body(day(claude: 900_000, codex: 300_000), scope: .all), "1.2M tokens\nClaude 900.0K \u{00B7} Codex 300.0K")
    }

    func testTitleIsTheDate() {
        XCTAssertEqual(ReportDayText.title(day(claude: 1, codex: 0), calendar: calendar, locale: locale), "Wed, Oct 14")
    }

    func testSummaryNamesActiveDaysAndTheBusiestDay() {
        let busiest = day(claude: 1_200_000, codex: 0)
        let series = ReportDaySeries(
            days: [busiest], activeDays: 21, daysUpToToday: 31, longestStreak: 6, busiest: busiest, dailyAverage: nil
        )
        let idle = ReportDaySeries(days: [], activeDays: 0, daysUpToToday: 31, longestStreak: 0, busiest: nil, dailyAverage: nil)

        XCTAssertEqual(ReportDayText.summary(series, calendar: calendar, locale: locale),
                       "Used on 21 of 31 days, busiest day Wed, Oct 14 with 1.2M tokens")
        XCTAssertEqual(ReportDayText.summary(idle, calendar: calendar, locale: locale), "No use in this period")
        XCTAssertEqual(ReportDayText.activeDaysUnit(series), "of 31 days")
    }
}
