@testable import Spark
import XCTest

final class HistoryHoverTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC") ?? .current
    private let base = Date(timeIntervalSince1970: 1_791_472_800) // 2026-10-08 15:20 UTC

    private func empty(_ slot: Int) -> HistoryColumn {
        HistoryColumn(session: nil, weekly: nil, slotStart: base.addingTimeInterval(Double(slot) * 600))
    }

    private func filled(_ slot: Int, _ session: Double) -> HistoryColumn {
        let start = base.addingTimeInterval(Double(slot) * 600)
        return HistoryColumn(session: session, weekly: 60, time: start.addingTimeInterval(60), slotStart: start)
    }

    func testLongEmptyRunsCollapseIntoOneGap() {
        let columns = [filled(0, 10), empty(1), empty(2), empty(3), empty(4), filled(5, 20), empty(6), filled(7, 30)]
        XCTAssertEqual(
            HistoryLayout.items(columns),
            [.column(0), .gap(1..<5), .column(5), .column(6), .column(7)]
        )
    }

    func testPointerPicksTheItemUnderIt() {
        let items: [HistoryItem] = [.column(0), .gap(1..<5), .column(5), .column(6)]
        XCTAssertEqual(HistoryLayout.index(x: 30, width: 100, count: items.count), 1)
        XCTAssertEqual(HistoryLayout.index(x: -5, width: 100, count: items.count), 0)
        XCTAssertEqual(HistoryLayout.index(x: 140, width: 100, count: items.count), 3)
        XCTAssertNil(HistoryLayout.index(x: 50, width: 0, count: items.count))
    }

    func testColumnTextShowsTimeAndBothValues() {
        let text = HistoryHover.text(for: .column(0), in: [filled(0, 45)], locale: Locale(identifier: "de_DE"), timeZone: utc)
        XCTAssertEqual(text?.title, "15:21")
        XCTAssertEqual(text?.body, "Session 45\u{00A0}%\nWeek 60\u{00A0}%")
        XCTAssertNil(HistoryHover.text(for: .column(0), in: [empty(0)]))
    }

    func testGapTextNamesTheMissingSpan() {
        let columns = [filled(0, 10), empty(1), empty(2), empty(3), filled(4, 20)]
        let text = HistoryHover.text(for: .gap(1..<4), in: columns, locale: Locale(identifier: "de_DE"), timeZone: utc)
        XCTAssertEqual(text?.title, "15:30\u{2013}16:00")
        XCTAssertEqual(text?.body, "No data here. The Mac may have slept, or Spark was closed or polling slowly")
    }

    func testAxisLabelsFollowTheCompressedItems() {
        let columns = [filled(0, 10), empty(1), empty(2), empty(3), filled(4, 20), filled(5, 30)]
        let items = HistoryLayout.items(columns)
        XCTAssertEqual(
            HistoryAxis.labels(items: items, columns: columns, locale: Locale(identifier: "de_DE"), timeZone: utc),
            ["15:20", "16:00", "16:11"]
        )
    }
}
