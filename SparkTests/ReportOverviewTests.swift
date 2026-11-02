@testable import Spark
import XCTest

final class ReportComparisonTests: XCTestCase {
    private let locale = Locale(identifier: "en_GB")
    private let utc = TimeZone(identifier: "UTC") ?? .current

    private func day(_ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: 2026, month: month, day: day)) ?? .distantPast
    }

    private func comparison(_ percent: Double?, _ period: ReportPeriod, from start: Date, to end: Date? = nil) -> String? {
        ReportText.comparison(percent, period: period, previousStart: start, previousEnd: end, locale: locale, timeZone: utc)
    }

    func testAFinishedMonthIsComparedWithThePreviousMonthByName() {
        XCTAssertEqual(comparison(9.4, .month, from: day(9, 1)), "+9% vs. September")
    }

    func testAPartialMonthNamesTheDaysItIsComparedWith() {
        XCTAssertEqual(comparison(4, .month, from: day(10, 1), to: day(10, 14)), "+4% vs. 1\u{2013}14 Oct")
        XCTAssertEqual(comparison(4, .month, from: day(10, 1), to: day(10, 1)), "+4% vs. 1 Oct")
    }

    func testAWeekIsComparedWithTheWeekBefore() {
        XCTAssertEqual(comparison(-5.6, .week, from: day(10, 5)), "-6% vs. last week")
        XCTAssertEqual(comparison(0.3, .week, from: day(10, 5)), "0% vs. last week")
    }

    func testNothingToCompareWithGivesNoLine() {
        XCTAssertNil(comparison(nil, .week, from: day(10, 5)))
        XCTAssertNil(comparison(.infinity, .week, from: day(10, 5)))
    }

    func testThePreviousTokensNameThePeriodTheyCover() {
        XCTAssertEqual(ReportText.previousTokens(1_200_000, period: .month, partialDays: 14), "1.2M tokens in the first 14 days of the month before")
        XCTAssertEqual(ReportText.previousTokens(1_200_000, period: .month, partialDays: 1), "1.2M tokens in the first 1 day of the month before")
        XCTAssertEqual(ReportText.previousTokens(1_200_000, period: .month, partialDays: nil), "1.2M tokens the month before")
        XCTAssertEqual(ReportText.previousTokens(500, period: .week, partialDays: nil), "500 tokens the week before")
    }

    func testTheTokensShrinkOnlyWhenTheValueIsTooLong() {
        XCTAssertEqual(ReportLayout.tokensSize("4.7"), 52)
        XCTAssertEqual(ReportLayout.tokensSize("286.9"), 52)
        XCTAssertEqual(ReportLayout.tokensSize("1234.5"), 44)
        XCTAssertEqual(ReportLayout.tokensSize("12345.67"), 36)
    }
}

final class ReportOverviewScopingTests: XCTestCase {
    private let calendar = TestCalendar.berlin()

    /// Week of 2026-08-14 to 2026-08-20, as in `ReportScopingTests`.
    private func report(sessions: Int = 7, claude: Int = 1000) -> PeriodReport {
        PeriodReport.build(
            rollups: ["2026-08-15": DailyRollup(sessionCount: 1, input: claude)], sessionCount: sessions,
            now: TestCalendar.date("2026-08-21"), calendar: calendar
        )
    }

    private let codex = CodexReportData(dayTokens: ["2026-08-16": 300, "2026-08-01": 999], modelTokens: [:], sessionCount: 3)

    func testSessionsAddUpPerScope() {
        XCTAssertEqual(ReportScoping.sessionCount(.all, report: report(), codex: codex), 10)
        XCTAssertEqual(ReportScoping.sessionCount(.claude, report: report(), codex: codex), 7)
        XCTAssertEqual(ReportScoping.sessionCount(.codex, report: report(), codex: codex), 3)
        XCTAssertEqual(ReportScoping.sessionCount(.all, report: report(), codex: nil), 7)
    }

    func testTheSplitSharesThePeriodsTokensClaudeFirst() {
        let split = ReportScoping.providerSplit(report: report(), codex: codex, calendar: calendar)

        XCTAssertEqual(split.map(\.provider), [.claude, .codex])
        XCTAssertEqual(split.map(\.tokens), [1000, 300])
        XCTAssertEqual(split[0].percent, 76.92, accuracy: 0.01)
        XCTAssertEqual(split[1].percent, 23.08, accuracy: 0.01)
    }

    func testASplitWithoutTokensSharesNothing() {
        let split = ReportScoping.providerSplit(report: report(claude: 0), codex: nil, calendar: calendar)

        XCTAssertEqual(split.map(\.percent), [0, 0])
    }
}

final class ReportOverviewDaysTests: XCTestCase {
    private let calendar = TestCalendar.berlin()
    private let locale = Locale(identifier: "en_US")

    private func key(_ date: Date) -> String { TranscriptCache.dayKey(for: date, calendar: calendar) }

    private func range(_ period: ReportPeriod, offset: Int = 0) -> [String] {
        let report = PeriodReport.build(rollups: [:], period: period, periodOffset: offset, now: TestCalendar.date("2026-08-21"), calendar: calendar)
        let range = ReportDaySeries.range(for: report, calendar: calendar)
        return [key(range.start), key(range.end)]
    }

    func testTheCurrentWeekEndsToday() {
        XCTAssertEqual(range(.week), ["2026-08-15", "2026-08-21"])
    }

    func testAMonthShowsEveryDayOfIt() {
        XCTAssertEqual(range(.month), ["2026-08-01", "2026-08-31"])
        XCTAssertEqual(range(.month, offset: 1), ["2026-07-01", "2026-07-31"])
    }

    func testAnEarlierWeekIsItsOwnSevenDays() {
        XCTAssertEqual(range(.week, offset: 1), ["2026-08-07", "2026-08-13"])
    }

    private func series(_ claude: [String: Int]) -> ReportDaySeries {
        ReportDaySeries.make(
            claude: claude, codex: [:], scope: .claude, start: TestCalendar.date("2026-08-10"), end: TestCalendar.date("2026-08-16"),
            now: TestCalendar.date("2026-08-16"), calendar: calendar, locale: locale
        )
    }

    func testTheOverviewLineNamesActiveDaysAndTheBusiestDay() {
        let line = ReportDayText.overviewLine(series(["2026-08-10": 100, "2026-08-12": 1_200_000]), calendar: calendar, locale: locale)

        XCTAssertEqual(line, "2 of 7 days active \u{00B7} busiest Wed, Aug 12, 1.2M tokens")
    }

    func testTheOverviewLineWithoutUse() {
        XCTAssertEqual(ReportDayText.overviewLine(series([:]), calendar: calendar, locale: locale), "No use in this period")
    }

    func testTheActivityCardSaysWhatItOpensAndItsFigure() {
        XCTAssertEqual(ReportCardText.activity(series(["2026-08-10": 100, "2026-08-12": 50])), "Open Activity, 2 of 7 days active")
    }
}

final class ReportCardTextTests: XCTestCase {
    private let calendar = TestCalendar.berlin()
    private let locale = Locale(identifier: "en_US")

    private func limits(_ provider: ReportProvider, _ snapshots: [UsageSnapshot]) -> ReportLimits {
        ReportLimits.make(
            provider: provider, snapshots: snapshots, start: TestCalendar.date("2026-08-10"), end: TestCalendar.date("2026-08-13"),
            calendar: calendar, locale: locale
        )
    }

    func testTheLimitsCardNamesEachProvidersSummary() {
        let claude = limits(.claude, [UsageSnapshot(timestamp: TestCalendar.date("2026-08-11"), sessionUtilization: 100, weeklyUtilization: 60)])
        let codex = limits(.codex, [])

        XCTAssertEqual(
            ReportCardText.limits([claude, codex]),
            "Open Limits, Claude: up to 60% \u{00B7} 1\u{00D7} at limit; Codex: No limit history for that period."
        )
    }

    private func row(_ name: String, tokens: Int) -> ReportBreakdownRow {
        ReportBreakdownRow(id: name, name: name, providers: [], detail: "", tokens: tokens, barPercent: 100, tooltip: "")
    }

    func testTheBreakdownCardsNameTheirTabAndTopRow() {
        XCTAssertEqual(
            ReportCardText.breakdown(.models, rows: [row("Opus", tokens: 2_300_000), row("Sonnet", tokens: 10)]),
            "Open Breakdown, Models, top Opus with 2.3M tokens"
        )
        XCTAssertEqual(ReportCardText.breakdown(.projects, rows: []), "Open Breakdown, Projects")
    }
}
