import XCTest
@testable import Spark

final class PaceDaySeriesTests: XCTestCase {
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

    private func snapshot(_ day: String, time: String = "12:00", session: Double, weekly: Double) -> UsageSnapshot {
        UsageSnapshot(timestamp: date(day, time: time), sessionUtilization: session, weeklyUtilization: weekly)
    }

    private func build(_ snapshots: [UsageSnapshot], start: String, end: String) -> [PaceDay] {
        PaceDaySeries.build(snapshots: snapshots, start: date(start), end: date(end), calendar: calendar)
    }

    func testYieldsOneEntryPerCalendarDayInclusiveOfBothEndpoints() {
        let days = build([], start: "2026-08-18", end: "2026-08-20")

        XCTAssertEqual(days.map(\.day), [date("2026-08-18"), date("2026-08-19"), date("2026-08-20")].map { calendar.startOfDay(for: $0) })
    }

    func testDaysWithNoSnapshotAreNilNotZero() {
        let days = build([], start: "2026-08-18", end: "2026-08-18")

        XCTAssertNil(days.first?.sessionUtilization)
        XCTAssertNil(days.first?.weeklyUtilization)
    }

    func testUsesThePeakUtilizationOfTheDayNotTheLastSample() {
        let snapshots = [
            snapshot("2026-08-18", time: "08:00", session: 20, weekly: 10),
            snapshot("2026-08-18", time: "12:00", session: 90, weekly: 40),
            snapshot("2026-08-18", time: "16:00", session: 5, weekly: 60) // dropped after a 5h reset
        ]

        let days = build(snapshots, start: "2026-08-18", end: "2026-08-18")

        XCTAssertEqual(days.first?.sessionUtilization, 90)
        XCTAssertEqual(days.first?.weeklyUtilization, 60)
    }

    func testSnapshotsOutsideTheRangeAreExcluded() {
        let snapshots = [
            snapshot("2026-08-17", session: 99, weekly: 99), // one day before the range
            snapshot("2026-08-18", session: 50, weekly: 50)
        ]

        let days = build(snapshots, start: "2026-08-18", end: "2026-08-18")

        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days.first?.sessionUtilization, 50)
    }

    func testEmptyRangeWhereEndPrecedesStartReturnsNoDays() {
        let days = build([], start: "2026-08-18", end: "2026-08-17")

        XCTAssertTrue(days.isEmpty)
    }

    func testEachDayOnlyAggregatesItsOwnSnapshots() {
        let snapshots = [
            snapshot("2026-08-18", session: 30, weekly: 10),
            snapshot("2026-08-19", session: 80, weekly: 20)
        ]

        let days = build(snapshots, start: "2026-08-18", end: "2026-08-19")

        XCTAssertEqual(days[0].sessionUtilization, 30)
        XCTAssertEqual(days[1].sessionUtilization, 80)
    }

    /// Regression for the day-accumulation drift bug also fixed in `PeriodReport.sum` and
    /// `PaceGraph.dayTicks`: without re-normalizing to `startOfDay` after `date(byAdding:)`, a
    /// DST transition at midnight silently drops the range's last day.
    func testSurvivesADaylightSavingTransitionAtMidnight() {
        var santiago = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        santiago.timeZone = TimeZone(identifier: "America/Santiago")!

        let days = PaceDaySeries.build(
            snapshots: [],
            start: date("2026-09-01"),
            end: date("2026-09-30"),
            calendar: santiago
        )

        XCTAssertEqual(days.count, 30, "every day of September, including the 30th, must be present")
    }
}
