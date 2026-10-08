@testable import Spark
import XCTest

final class HistoryDetailTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC") ?? .current
    private let base = Date(timeIntervalSince1970: 1_791_472_800) // 2026-10-08 15:20 UTC

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }

    private func snapshot(_ minutes: Double, session: Double, weekly: Double) -> UsageSnapshot {
        UsageSnapshot(timestamp: base.addingTimeInterval(minutes * 60), sessionUtilization: session, weeklyUtilization: weekly)
    }

    // MARK: - Ranges

    func testEachRangeKeepsSlotsAtLeastAPollApart() {
        for range in GraphTimeRange.allCases {
            XCTAssertGreaterThanOrEqual(range.seconds / Double(range.columnCount), 300, "\(range)")
            XCTAssertLessThanOrEqual(range.columnCount, 48, "\(range)")
        }
    }

    // MARK: - Summary

    func testSummaryReadsPeakSessionAndWeeklyPointsAdded() {
        let snapshots = [
            snapshot(0, session: 20, weekly: 40),
            snapshot(10, session: 88, weekly: 46),
            snapshot(20, session: 5, weekly: 2),
            snapshot(30, session: 30, weekly: 6)
        ]
        let summary = HistorySummary.make(snapshots)
        XCTAssertEqual(summary.peakSession, 88)
        // 40 to 46, then a reset to 2 that is not subtracted, then 2 to 6.
        XCTAssertEqual(summary.weekAdded, 10)
    }

    func testSummaryWithoutEnoughDataIsEmpty() {
        XCTAssertEqual(HistorySummary.make([]), HistorySummary(peakSession: nil, weekAdded: nil))
        XCTAssertEqual(HistorySummary.make([snapshot(0, session: 12, weekly: 3)]), HistorySummary(peakSession: 12, weekAdded: nil))
    }

    func testWeekPointsAreSignedAndRounded() {
        XCTAssertEqual(HistorySummary.points(10.4), NumberParts(number: "+10", unit: "pts"))
        XCTAssertEqual(HistorySummary.points(0.2), NumberParts(number: "0", unit: "pts"))
        XCTAssertEqual(HistorySummary.points(1), NumberParts(number: "+1", unit: "pt"))
    }

    // MARK: - Dated labels

    func testLongRangesLabelTheAxisWithDays() {
        let columns = (0..<3).map { HistoryColumn(session: 10, weekly: 20, slotStart: base.addingTimeInterval(Double($0) * 86_400)) }
        let labels = HistoryAxis.labels(
            items: HistoryLayout.items(columns), columns: columns, locale: Locale(identifier: "en_GB"), timeZone: utc, includesDate: true
        )
        XCTAssertEqual(labels, ["8 Oct", "9 Oct", "10 Oct"])
    }

    func testLongRangesNameTheDayInTheReadout() {
        let column = HistoryColumn(session: 45, weekly: 60, time: base.addingTimeInterval(60), slotStart: base)
        let text = HistoryHover.text(for: .column(0), in: [column], locale: Locale(identifier: "en_GB"), timeZone: utc, includesDate: true)
        XCTAssertEqual(text?.title, "Thu 8 Oct at 15:21")
    }

    // MARK: - Volume

    private func day(_ offset: Int, _ tokens: Int, hasRollup: Bool = true) -> VolumeDay {
        let date = base.addingTimeInterval(Double(offset) * 86_400)
        return VolumeDay(day: TranscriptCache.dayKey(for: date, calendar: calendar), tokens: tokens, hasRollup: hasRollup)
    }

    func testVolumeColumnsScaleToTheBusiestDay() {
        let columns = VolumeColumns.make([day(0, 500), day(1, 0, hasRollup: false), day(2, 1000)], calendar: calendar)
        XCTAssertEqual(columns.map(\.session), [50, nil, 100])
        XCTAssertEqual(columns.map(\.weekly), [nil, nil, nil])
        XCTAssertEqual(columns.first?.slotStart, calendar.startOfDay(for: base))
    }

    func testVolumeSummaryAveragesOnlyDaysWithData() {
        let summary = VolumeSummary.make([day(0, 500), day(1, 0, hasRollup: false), day(2, 1000)])
        XCTAssertEqual(summary, VolumeSummary(total: 1500, dailyAverage: 750))
        XCTAssertEqual(VolumeSummary.make([day(0, 0, hasRollup: false)]), VolumeSummary(total: 0, dailyAverage: nil))
    }

    func testVolumeReadoutNamesTheDayAndTokens() {
        let days = [day(0, 6_800_000), day(1, 0, hasRollup: false)]
        let columns = VolumeColumns.make(days, calendar: calendar)
        let locale = Locale(identifier: "en_GB")
        XCTAssertEqual(VolumeHover.text(for: .column(0), days: days, columns: columns, locale: locale, timeZone: utc)?.body, "6.8M tokens")
        XCTAssertEqual(VolumeHover.text(for: .column(0), days: days, columns: columns, locale: locale, timeZone: utc)?.title, "Thu 8 Oct")
        XCTAssertEqual(VolumeHover.text(for: .column(1), days: days, columns: columns, locale: locale, timeZone: utc)?.body, "No data")
    }
}
