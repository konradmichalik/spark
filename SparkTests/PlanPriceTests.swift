@testable import Spark
import XCTest

final class PlanPriceTests: XCTestCase {
    private let calendar = TestCalendar.berlin()

    // MARK: - Monthly price

    func testListPricesFollowThePlan() {
        XCTAssertEqual(PlanPrice.listPrice(for: AccountTier(plan: "Pro", multiplier: nil)), 20)
        XCTAssertEqual(PlanPrice.listPrice(for: AccountTier(plan: "Max", multiplier: "5x")), 100)
        XCTAssertEqual(PlanPrice.listPrice(for: AccountTier(plan: "Max", multiplier: "20x")), 200)
    }

    func testPlansWithoutAListPriceHaveNone() {
        XCTAssertNil(PlanPrice.listPrice(for: .free))
        XCTAssertNil(PlanPrice.listPrice(for: AccountTier(plan: "Team", multiplier: "5x")))
        XCTAssertNil(PlanPrice.listPrice(for: AccountTier(plan: "Enterprise", multiplier: nil)))
    }

    func testAPriceFromTheSettingWinsOverTheListPrice() {
        let max = AccountTier(plan: "Max", multiplier: nil)
        XCTAssertEqual(PlanPrice.monthly(setting: 0, tier: max), 100)
        XCTAssertEqual(PlanPrice.monthly(setting: 90, tier: max), 90)
        XCTAssertEqual(PlanPrice.monthly(setting: 125, tier: AccountTier(plan: "Team", multiplier: "5x")), 125)
        XCTAssertNil(PlanPrice.monthly(setting: 0, tier: .free))
    }

    // MARK: - Days

    func testRollingPeriodsCountTheCalendarDaysTheScanKeeps() {
        let now = TestCalendar.date("2026-10-31")
        XCTAssertEqual(PlanPrice.days(for: .today, dayTokens: [:], now: now, calendar: calendar), 1)
        XCTAssertEqual(PlanPrice.days(for: .week, dayTokens: [:], now: now, calendar: calendar), 8)
        XCTAssertEqual(PlanPrice.days(for: .month, dayTokens: [:], now: now, calendar: calendar), 31)
    }

    func testAllTimeRunsFromTheFirstDayWithTokens() {
        let now = TestCalendar.date("2026-10-31")
        let dayTokens = ["2026-10-02": 10, "2026-09-22": 0, "2026-10-01": 5]
        XCTAssertEqual(PlanPrice.days(for: .all, dayTokens: dayTokens, now: now, calendar: calendar), 31)
        XCTAssertNil(PlanPrice.days(for: .all, dayTokens: [:], now: now, calendar: calendar))
    }

    func testTheCurrentReportCountsTodayLikeItsCostScan() {
        let now = TestCalendar.date("2026-10-31")
        let week = PeriodReport.build(rollups: [:], period: .week, periodOffset: 0, now: now, calendar: calendar)
        XCTAssertEqual(week.costDayCount(now: now, calendar: calendar), 8)
        let firstOfMonth = TestCalendar.date("2026-10-01")
        let month = PeriodReport.build(rollups: [:], period: .month, periodOffset: 0, now: firstOfMonth, calendar: calendar)
        XCTAssertEqual(month.costDayCount(now: firstOfMonth, calendar: calendar), 1)
    }

    func testAPastReportCountsItsWholeRange() {
        let now = TestCalendar.date("2026-10-31")
        let september = PeriodReport.build(rollups: [:], period: .month, periodOffset: 1, now: now, calendar: calendar)
        XCTAssertEqual(september.costDayCount(now: now, calendar: calendar), 30)
    }

    // MARK: - Value

    func testThePlanShareIsTheMonthlyPriceSpreadOverTheDays() throws {
        let value = try XCTUnwrap(PlanValue(apiCost: 120, monthlyPrice: 100, days: 7))
        XCTAssertEqual(value.planShare, 100 * 7 / (365.25 / 12), accuracy: 0.0001)
        XCTAssertEqual(value.multiple, 120 / value.planShare, accuracy: 0.0001)
        XCTAssertEqual(value.days, 7)
        XCTAssertEqual(value.monthlyPrice, 100)
    }

    func testNoValueWithoutAPriceOrDays() {
        XCTAssertNil(PlanValue(apiCost: 120, monthlyPrice: nil, days: 7))
        XCTAssertNil(PlanValue(apiCost: 120, monthlyPrice: 0, days: 7))
        XCTAssertNil(PlanValue(apiCost: 120, monthlyPrice: 100, days: nil))
        XCTAssertNil(PlanValue(apiCost: 120, monthlyPrice: 100, days: 0))
    }

    // MARK: - Wording

    func testMultipleFitsATile() {
        XCTAssertEqual(UsageFormat.multiple(5.43), NumberParts(number: "5.4", unit: "\u{00D7}"))
        XCTAssertEqual(UsageFormat.multiple(9.96), NumberParts(number: "10", unit: "\u{00D7}"))
        XCTAssertEqual(UsageFormat.multiple(1234.4), NumberParts(number: "1,234", unit: "\u{00D7}"))
        XCTAssertEqual(UsageFormat.multiple(12_345), NumberParts(number: "12.3", unit: "K\u{00D7}"))
        XCTAssertEqual(UsageFormat.multiple(-1), NumberParts(number: "0.0", unit: "\u{00D7}"))
    }

    func testTooltipNamesThePlanShareAndTheLimit() throws {
        let value = try XCTUnwrap(PlanValue(apiCost: 120, monthlyPrice: 100, days: 7))
        XCTAssertEqual(
            StatisticsText.planValueTooltip(value),
            "API cost against the plan share of \u{2248} $23.00 for 7 days, at $100.00 a month.\n"
                + "Only Claude Code on this Mac counts, so the real value is higher."
        )
        let day = try XCTUnwrap(PlanValue(apiCost: 4, monthlyPrice: 100, days: 1))
        XCTAssertTrue(StatisticsText.planValueTooltip(day).contains("for 1 day,"))
    }

    func testReportCostTooltipAddsThePlanShare() throws {
        let cost = CostSummary(total: 120, byModel: [:], byProject: [:], bySession: [:], unpricedModels: [])
        let value = try XCTUnwrap(PlanValue(apiCost: 120, monthlyPrice: 100, days: 7))
        XCTAssertEqual(
            StatisticsText.costTooltip(cost, planValue: value),
            "Estimated: tokens priced at API list prices. Not what your subscription costs.\n"
                + "5.2\u{00D7} the plan share of \u{2248} $23.00 for 7 days."
        )
        XCTAssertEqual(StatisticsText.costTooltip(cost, planValue: nil), StatisticsText.costTooltip(cost))
    }
}
