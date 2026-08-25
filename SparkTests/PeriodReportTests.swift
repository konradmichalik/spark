import XCTest
@testable import Spark

final class PeriodReportTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func date(_ day: String, time: String = "12:00") -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        // swiftlint:disable:next force_unwrapping
        return formatter.date(from: "\(day) \(time)")!
    }

    private func build(
        _ rollups: [String: DailyRollup],
        modelTotals: [String: Int] = [:],
        topProjects: [ProjectUsage] = [],
        period: ReportPeriod = .week,
        offset: Int = 0,
        now: String = "2026-08-21"
    ) -> PeriodReport {
        PeriodReport.build(
            rollups: rollups,
            modelTotals: modelTotals,
            topProjects: topProjects,
            period: period,
            periodOffset: offset,
            now: date(now),
            calendar: calendar
        )
    }

    private func dayString(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: value)
    }

    private func windowStart(
        _ rollups: [String: DailyRollup],
        period: ReportPeriod = .week,
        offset: Int = 0,
        now: String = "2026-08-21"
    ) -> String {
        dayString(PeriodReport.windowStart(period: period, periodOffset: offset, rollups: rollups, now: date(now), calendar: calendar))
    }

    private func windowEnd(
        _ rollups: [String: DailyRollup],
        period: ReportPeriod = .week,
        offset: Int = 0,
        now: String = "2026-08-21"
    ) -> String? {
        PeriodReport.windowEnd(period: period, periodOffset: offset, rollups: rollups, now: date(now), calendar: calendar).map(dayString)
    }

    // MARK: - Week window boundaries

    func testCurrentWeekSumsTheSevenMostRecentClosedDays() {
        let report = build([
            "2026-08-13": DailyRollup(sessionCount: 1, input: 999), // outside the window (previous week)
            "2026-08-15": DailyRollup(sessionCount: 1, input: 10),
            "2026-08-20": DailyRollup(sessionCount: 1, input: 20)
        ])

        XCTAssertEqual(report.currentPeriodTokens, 30)
    }

    func testCurrentWeekIncludesTheOldestDayOfTheSevenDayWindow() {
        // 2026-08-14 is exactly 6 days before the window's last day (2026-08-20) — the far edge
        // of the current window, not yet the previous week.
        let report = build(["2026-08-14": DailyRollup(sessionCount: 1, input: 5)])

        XCTAssertEqual(report.currentPeriodTokens, 5)
    }

    func testPreviousWeekSumsTheSevenDaysBeforeThat() {
        let report = build([
            "2026-08-08": DailyRollup(sessionCount: 1, input: 40),
            "2026-08-20": DailyRollup(sessionCount: 1, input: 20)
        ])

        XCTAssertEqual(report.previousPeriodTokens, 40)
    }

    /// Mirrors `VolumeDaySeries`: today carries no rollup until it closes, so the window ends on
    /// the last closed day unless today already has a rollup.
    func testWindowEndsYesterdayUnlessTodayHasARollup() {
        let withoutToday = build(["2026-08-20": DailyRollup(sessionCount: 1, input: 20)])
        XCTAssertEqual(withoutToday.currentPeriodTokens, 20)

        let withToday = build(["2026-08-21": DailyRollup(sessionCount: 1, input: 20)])
        XCTAssertEqual(withToday.currentPeriodTokens, 20)
    }

    func testWindowStartAlignsWithTheFirstDayOfTheCurrentWindow() {
        XCTAssertEqual(windowStart(["2026-08-20": DailyRollup(sessionCount: 1, input: 20)]), "2026-08-14")
        XCTAssertEqual(windowStart(["2026-08-21": DailyRollup(sessionCount: 1, input: 20)]), "2026-08-15")
    }

    // MARK: - Real tokens (cache reads excluded)

    func testWeeklyTotalsExcludeCacheReads() {
        let report = build([
            "2026-08-20": DailyRollup(sessionCount: 1, input: 10, output: 5, cacheCreation: 2, cacheRead: 1_000)
        ])

        XCTAssertEqual(report.currentPeriodTokens, 17)
    }

    // MARK: - Trend

    func testTrendPercentIsNilWhenPreviousWeekHasNoRollupsAtAll() {
        let report = build(["2026-08-20": DailyRollup(sessionCount: 1, input: 20)])

        XCTAssertNil(report.trendPercent)
    }

    func testTrendPercentIsNilWhenPreviousWeekRollupsSumToZero() {
        let report = build([
            "2026-08-08": DailyRollup(sessionCount: 1), // a real, closed day with zero tokens
            "2026-08-20": DailyRollup(sessionCount: 1, input: 20)
        ])

        XCTAssertNil(report.trendPercent)
    }

    func testTrendPercentIsZeroWhenBothWeeksMatch() {
        let report = build([
            "2026-08-08": DailyRollup(sessionCount: 1, input: 100),
            "2026-08-20": DailyRollup(sessionCount: 1, input: 100)
        ])

        XCTAssertEqual(report.trendPercent ?? .nan, 0, accuracy: 0.001)
    }

    func testTrendPercentIsPositiveWhenCurrentWeekIsHigher() {
        let report = build([
            "2026-08-08": DailyRollup(sessionCount: 1, input: 100), // previous week
            "2026-08-20": DailyRollup(sessionCount: 1, input: 150) // current week
        ])

        XCTAssertEqual(report.trendPercent ?? .nan, 50, accuracy: 0.001)
    }

    func testTrendPercentIsNegativeWhenCurrentWeekIsLower() {
        let report = build([
            "2026-08-08": DailyRollup(sessionCount: 1, input: 200), // previous week
            "2026-08-20": DailyRollup(sessionCount: 1, input: 50) // current week
        ])

        XCTAssertEqual(report.trendPercent ?? .nan, -75, accuracy: 0.001)
    }

    // MARK: - Caller-supplied model totals / top projects

    func testModelTotalsPassThroughUnchanged() {
        let report = build([:], modelTotals: ["claude-sonnet-4-6": 15])

        XCTAssertEqual(report.modelTotals["claude-sonnet-4-6"], 15)
    }

    func testTopProjectsPassThroughUnchanged() {
        let projects = [ProjectUsage(key: "-Users-me-app", displayName: "app", tokens: 42)]
        let report = build([:], topProjects: projects)

        XCTAssertEqual(report.topProjects.map(\.key), ["-Users-me-app"])
    }

    // MARK: - hasData

    func testHasDataIsFalseWhenNothingWasFound() {
        let report = build([:])

        XCTAssertFalse(report.hasData)
    }

    func testHasDataIsTrueWhenOnlyTopProjectsAreNonEmpty() {
        let report = build([:], topProjects: [ProjectUsage(key: "-Users-me-app", displayName: "app", tokens: 1)])

        XCTAssertTrue(report.hasData)
    }

    // MARK: - Week navigation (periodOffset)

    func testWeekOffsetOneShowsTheWeekBeforeTheCurrentOne() {
        let report = build([
            "2026-08-13": DailyRollup(sessionCount: 1, input: 30), // shown week (offset 1)
            "2026-08-20": DailyRollup(sessionCount: 1, input: 999) // current week — must be excluded
        ], offset: 1)

        XCTAssertEqual(report.currentPeriodTokens, 30)
    }

    func testWeekOffsetShiftsThePreviousWeekBackByTheSameAmount() {
        let report = build([
            "2026-08-06": DailyRollup(sessionCount: 1, input: 10), // previous week relative to offset 1
            "2026-08-13": DailyRollup(sessionCount: 1, input: 30) // shown week (offset 1)
        ], offset: 1)

        XCTAssertEqual(report.currentPeriodTokens, 30)
        XCTAssertEqual(report.previousPeriodTokens, 10)
    }

    func testRangeStartAndEndMatchTheShownWeeksBoundaries() {
        let report = build(["2026-08-20": DailyRollup(sessionCount: 1, input: 1)])

        XCTAssertEqual(dayString(report.rangeStart), "2026-08-14")
        XCTAssertEqual(dayString(report.rangeEnd), "2026-08-20")
    }

    func testRangeShiftsBackByWholeWeeksWithOffset() {
        let report = build(["2026-08-13": DailyRollup(sessionCount: 1, input: 1)], offset: 1)

        XCTAssertEqual(dayString(report.rangeStart), "2026-08-07")
        XCTAssertEqual(dayString(report.rangeEnd), "2026-08-13")
        XCTAssertEqual(report.periodOffset, 1)
    }

    func testWindowStartShiftsBackByWholeWeeksWithOffset() {
        XCTAssertEqual(
            windowStart(["2026-08-20": DailyRollup(sessionCount: 1, input: 1)], offset: 1),
            "2026-08-07"
        )
    }

    func testWindowEndIsNilForTheCurrentWeek() {
        XCTAssertNil(windowEnd(["2026-08-20": DailyRollup(sessionCount: 1, input: 1)]))
    }

    func testWindowEndIsTheShownWeeksLastDayForAPastWeek() {
        XCTAssertEqual(
            windowEnd(["2026-08-20": DailyRollup(sessionCount: 1, input: 1)], offset: 1),
            "2026-08-13"
        )
    }

    func testHasEarlierPeriodIsTrueWhenARollupExistsBeforeTheShownWeek() {
        let rollups = ["2026-08-13": DailyRollup(sessionCount: 1, input: 5)]

        XCTAssertTrue(PeriodReport.hasEarlierPeriod(periodOffset: 0, rollups: rollups, now: date("2026-08-21"), calendar: calendar))
    }

    func testHasEarlierPeriodIsFalseWhenNoRollupPredatesTheShownWeek() {
        let rollups = ["2026-08-20": DailyRollup(sessionCount: 1, input: 5)]

        XCTAssertFalse(PeriodReport.hasEarlierPeriod(periodOffset: 0, rollups: rollups, now: date("2026-08-21"), calendar: calendar))
    }

    /// A week with zero activity produces no rollup for any of its days. That must not be
    /// mistaken for "no earlier history exists" — history from before the idle stretch is still
    /// reachable by continuing to navigate back.
    func testHasEarlierPeriodIsTrueAcrossAnEntirelyIdleWeek() {
        // Idle: 2026-08-07...08-13 (the week immediately before the shown one) has no rollups.
        let rollups = ["2026-07-30": DailyRollup(sessionCount: 1, input: 5)]

        XCTAssertTrue(PeriodReport.hasEarlierPeriod(periodOffset: 0, rollups: rollups, now: date("2026-08-21"), calendar: calendar))
    }

    func testHasEarlierPeriodAtANonZeroOffsetLooksBeforeTheShownWeekNotBeforeTheCurrentWeek() {
        // Shown week (offset 2) is 2026-07-31...08-06. A rollup inside offset 1's week
        // (08-07...08-13) must not count as "earlier" relative to offset 2.
        let rollups = ["2026-08-10": DailyRollup(sessionCount: 1, input: 5)]

        XCTAssertFalse(
            PeriodReport.hasEarlierPeriod(periodOffset: 2, rollups: rollups, now: date("2026-08-21"), calendar: calendar)
        )
    }

    // MARK: - windowStart/windowEnd bracket exactly what build() sums

    /// For a past week, `windowStart`/`windowEnd` are meant to bound a live scan to precisely the
    /// same days `build` sums rollups over. Proves that by construction: rollups exactly on each
    /// boundary count, rollups one day outside either boundary don't.
    func testWindowStartAndEndBracketExactlyTheDaysBuildSumsForAPastWeek() {
        let rollups = [
            "2026-08-06": DailyRollup(sessionCount: 1, input: 1), // one day before windowStart
            "2026-08-07": DailyRollup(sessionCount: 1, input: 1), // == windowStart
            "2026-08-13": DailyRollup(sessionCount: 1, input: 1), // == windowEnd
            "2026-08-14": DailyRollup(sessionCount: 1, input: 1) // one day after windowEnd
        ]

        XCTAssertEqual(windowStart(rollups, offset: 1), "2026-08-07")
        XCTAssertEqual(windowEnd(rollups, offset: 1), "2026-08-13")
        XCTAssertEqual(build(rollups, offset: 1).currentPeriodTokens, 2, "only the two in-bracket days should be summed")
    }

    // MARK: - Cache hit rate

    func testCacheHitRateIsNilWhenTheWeekHasNoCacheActivity() {
        let report = build(["2026-08-20": DailyRollup(sessionCount: 1, input: 10)])

        XCTAssertNil(report.cacheHitRate)
    }

    func testCacheHitRateAtANonZeroWeekOffsetOnlyCountsThatWeek() {
        let report = build([
            "2026-08-13": DailyRollup(sessionCount: 1, cacheCreation: 20, cacheRead: 80) // shown week (offset 1)
        ], offset: 1)

        XCTAssertEqual(report.cacheHitRate ?? .nan, 0.8, accuracy: 0.001)
    }

    func testCacheHitRateIsReadsOverReadsPlusCreation() {
        let report = build([
            "2026-08-20": DailyRollup(sessionCount: 1, cacheCreation: 25, cacheRead: 75)
        ])

        XCTAssertEqual(report.cacheHitRate ?? .nan, 0.75, accuracy: 0.001)
    }

    func testCacheHitRateOnlyCountsTheCurrentWeek() {
        let report = build([
            "2026-08-08": DailyRollup(sessionCount: 1, cacheCreation: 100, cacheRead: 0), // previous week
            "2026-08-20": DailyRollup(sessionCount: 1, cacheCreation: 0, cacheRead: 10) // current week
        ])

        XCTAssertEqual(report.cacheHitRate ?? .nan, 1.0, accuracy: 0.001)
    }

    // MARK: - Month window boundaries

    func testCurrentMonthSumsFromTheFirstOfTheMonthThroughYesterday() {
        let report = build([
            "2026-07-31": DailyRollup(sessionCount: 1, input: 999), // last day of the previous month
            "2026-08-01": DailyRollup(sessionCount: 1, input: 10),
            "2026-08-20": DailyRollup(sessionCount: 1, input: 20)
        ], period: .month, now: "2026-08-21")

        XCTAssertEqual(report.currentPeriodTokens, 30)
    }

    func testCurrentMonthEndsTodayWhenTodayIsAlreadyClosed() {
        let report = build(["2026-08-21": DailyRollup(sessionCount: 1, input: 5)], period: .month, now: "2026-08-21")

        XCTAssertEqual(report.currentPeriodTokens, 5)
    }

    func testPastMonthSpansTheFullCalendarMonth() {
        let report = build([
            "2026-07-01": DailyRollup(sessionCount: 1, input: 10), // first day of July
            "2026-07-31": DailyRollup(sessionCount: 1, input: 20), // last day of July
            "2026-06-30": DailyRollup(sessionCount: 1, input: 999), // last day of June — excluded
            "2026-08-01": DailyRollup(sessionCount: 1, input: 999) // first day of August — excluded
        ], period: .month, offset: 1, now: "2026-08-21")

        XCTAssertEqual(report.currentPeriodTokens, 30)
        XCTAssertEqual(dayString(report.rangeStart), "2026-07-01")
        XCTAssertEqual(dayString(report.rangeEnd), "2026-07-31")
    }

    func testPreviousMonthIsTheCalendarMonthBeforeTheShownOne() {
        let report = build([
            "2026-06-15": DailyRollup(sessionCount: 1, input: 40), // June — previous month relative to July
            "2026-07-15": DailyRollup(sessionCount: 1, input: 30) // shown month: July
        ], period: .month, offset: 1, now: "2026-08-21")

        XCTAssertEqual(report.currentPeriodTokens, 30)
        XCTAssertEqual(report.previousPeriodTokens, 40)
    }

    func testMonthWindowEndIsNilForTheCurrentMonthAndSetForAPastOne() {
        XCTAssertNil(windowEnd([:], period: .month, now: "2026-08-21"))
        XCTAssertEqual(windowEnd([:], period: .month, offset: 1, now: "2026-08-21"), "2026-07-31")
    }

    func testMonthWindowStartIsTheFirstOfTheShownMonth() {
        XCTAssertEqual(windowStart([:], period: .month, now: "2026-08-21"), "2026-08-01")
        XCTAssertEqual(windowStart([:], period: .month, offset: 1, now: "2026-08-21"), "2026-07-01")
        XCTAssertEqual(windowStart([:], period: .month, offset: 2, now: "2026-08-21"), "2026-06-01")
    }

    func testHasEarlierPeriodForMonthsLooksAcrossMonthBoundaries() {
        let rollups = ["2026-06-15": DailyRollup(sessionCount: 1, input: 5)]

        // Shown month at offset 0 is August — June predates it.
        XCTAssertTrue(
            PeriodReport.hasEarlierPeriod(period: .month, periodOffset: 0, rollups: rollups, now: date("2026-08-21"), calendar: calendar)
        )

        // Shown month at offset 2 is June itself — nothing predates its own month.
        XCTAssertFalse(
            PeriodReport.hasEarlierPeriod(period: .month, periodOffset: 2, rollups: rollups, now: date("2026-08-21"), calendar: calendar),
            "a rollup inside the shown month itself is not \"earlier\" than that month"
        )
    }

    func testHasEarlierPeriodForMonthsDoesNotCountTheImmediatelyFollowingMonth() {
        // A rollup in July must not count as "earlier" than June, the shown month at offset 2.
        let rollups = ["2026-07-15": DailyRollup(sessionCount: 1, input: 5)]

        XCTAssertFalse(
            PeriodReport.hasEarlierPeriod(period: .month, periodOffset: 2, rollups: rollups, now: date("2026-08-21"), calendar: calendar)
        )
    }

    func testCacheHitRateWorksForMonthPeriodToo() {
        let report = build([
            "2026-08-05": DailyRollup(sessionCount: 1, cacheCreation: 10, cacheRead: 90)
        ], period: .month, now: "2026-08-21")

        XCTAssertEqual(report.cacheHitRate ?? .nan, 0.9, accuracy: 0.001)
    }

    // MARK: - Month edge cases: day 1, February, year rollover

    /// On the 1st of the month, before today has closed, the month's window has no closed days
    /// at all — `rangeEnd` lands one day before `rangeStart`. `isEmptyWindow` exists precisely
    /// so the view can detect this and skip a misleading "0 tokens, down 100%".
    func testDayOneOfAMonthBeforeItClosesHasAnEmptyWindow() {
        let report = build([:], period: .month, now: "2026-03-01")

        XCTAssertEqual(report.currentPeriodTokens, 0)
        XCTAssertTrue(report.isEmptyWindow)
        XCTAssertTrue(report.rangeEnd < report.rangeStart)
    }

    func testFebruaryInALeapYearSpansTwentyNineDays() {
        // now = 2024-03-15, offset 1 -> shown month is February 2024 (a leap year).
        let end = windowEnd([:], period: .month, offset: 1, now: "2024-03-15")

        XCTAssertEqual(end, "2024-02-29")
    }

    func testFebruaryInANonLeapYearSpansTwentyEightDays() {
        let end = windowEnd([:], period: .month, offset: 1, now: "2023-03-15")

        XCTAssertEqual(end, "2023-02-28")
    }

    func testMonthNavigationRollsOverTheYearBoundary() {
        // now = 2026-01-15, offset 1 -> shown month is December of the previous year.
        XCTAssertEqual(windowStart([:], period: .month, offset: 1, now: "2026-01-15"), "2025-12-01")
        XCTAssertEqual(windowEnd([:], period: .month, offset: 1, now: "2026-01-15"), "2025-12-31")
    }

    func testHasEarlierPeriodForMonthsWorksAcrossTheYearBoundary() {
        let rollups = ["2025-11-15": DailyRollup(sessionCount: 1, input: 5)]

        XCTAssertTrue(
            PeriodReport.hasEarlierPeriod(period: .month, periodOffset: 1, rollups: rollups, now: date("2026-01-15"), calendar: calendar)
        )
    }

    /// Regression for a bug where the day-accumulation loop advanced by adding a day to the
    /// *previous result* instead of re-deriving from a fixed anchor: `date(byAdding:)` preserves
    /// wall-clock time, so once a DST transition shifted the cursor off midnight, the `day <=
    /// endDay` loop guard terminated one iteration early and silently dropped the period's last
    /// day. Santiago's fall-back transition happens at local midnight, which is exactly the case
    /// that broke.
    func testMonthSummingSurvivesADaylightSavingTransitionAtMidnight() {
        var santiago = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        santiago.timeZone = TimeZone(identifier: "America/Santiago")!

        var rollups: [String: DailyRollup] = [:]
        for day in 1...30 {
            rollups[String(format: "2026-09-%02d", day)] = DailyRollup(sessionCount: 1, input: 1)
        }

        let report = PeriodReport.build(
            rollups: rollups,
            period: .month,
            periodOffset: 1,
            now: date("2026-10-15"),
            calendar: santiago
        )

        XCTAssertEqual(report.currentPeriodTokens, 30, "every day of September, including the 30th, must be summed")
    }
}
