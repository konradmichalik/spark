import XCTest
@testable import Spark

final class VolumeDaySeriesTests: XCTestCase {
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

    private func rollup(tokens: Int) -> DailyRollup {
        DailyRollup(sessionCount: 1, input: tokens)
    }

    private func build(
        _ rollups: [String: DailyRollup],
        timeRange: GraphTimeRange = .sevenDays,
        now: String = "2026-08-21"
    ) -> [VolumeDay] {
        VolumeDaySeries.build(
            rollups: rollups,
            timeRange: timeRange,
            now: date(now),
            calendar: calendar
        )
    }

    func testSevenDayRangeAlwaysYieldsSevenLanesEndingYesterday() {
        let days = build(["2026-08-18": rollup(tokens: 100)])

        XCTAssertEqual(days.map(\.day), [
            "2026-08-14", "2026-08-15", "2026-08-16", "2026-08-17",
            "2026-08-18", "2026-08-19", "2026-08-20"
        ])
    }

    func testThirtyDayRangeYieldsThirtyLanes() {
        let days = build([:], timeRange: .thirtyDays)

        XCTAssertEqual(days.count, 30)
        XCTAssertEqual(days.first?.day, "2026-07-22")
        XCTAssertEqual(days.last?.day, "2026-08-20")
    }

    func testDaysWithoutRollupsBecomeEmptyLanes() {
        let days = build(["2026-08-18": rollup(tokens: 100)])

        XCTAssertEqual(days.filter(\.isEmpty).count, 6)
        XCTAssertEqual(days.first { $0.day == "2026-08-18" }?.tokens, 100)
        XCTAssertEqual(days.first { $0.day == "2026-08-18" }?.isEmpty, false)
    }

    func testLaneCountDoesNotChangeWithSparsity() {
        let sparse = build(["2026-08-18": rollup(tokens: 100)])
        let dense = build([
            "2026-08-14": rollup(tokens: 1),
            "2026-08-15": rollup(tokens: 2),
            "2026-08-16": rollup(tokens: 3),
            "2026-08-17": rollup(tokens: 4),
            "2026-08-18": rollup(tokens: 5),
            "2026-08-19": rollup(tokens: 6),
            "2026-08-20": rollup(tokens: 7)
        ])

        XCTAssertEqual(sparse.map(\.day), dense.map(\.day))
    }

    func testRollupsOutsideTheWindowAreExcluded() {
        let days = build([
            "2026-08-01": rollup(tokens: 100),
            "2026-08-20": rollup(tokens: 200)
        ])

        XCTAssertNil(days.first { $0.day == "2026-08-01" })
        XCTAssertEqual(days.last?.tokens, 200)
    }

    /// Today carries no rollup until it closes, so it would otherwise always draw as an idle
    /// lane — it only joins the window once a rollup for it exists.
    func testTodayJoinsTheWindowOnlyWhenItHasARollup() {
        let days = build(["2026-08-21": rollup(tokens: 100)])

        XCTAssertEqual(days.last?.day, "2026-08-21")
        XCTAssertEqual(days.first?.day, "2026-08-15")
    }

    func testTokensSumEveryRollupBucket() {
        let full = DailyRollup(sessionCount: 2, input: 1, output: 2, cacheCreation: 4, cacheRead: 8)
        let days = build(["2026-08-20": full])

        XCTAssertEqual(days.last?.tokens, 15)
    }
}
