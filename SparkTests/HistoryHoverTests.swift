@testable import Spark
import XCTest

final class HistoryHoverTests: XCTestCase {
    private let empty = HistoryColumn(session: nil, weekly: nil)

    private func filled(_ session: Double) -> HistoryColumn {
        HistoryColumn(session: session, weekly: 60, time: Date(timeIntervalSince1970: 0))
    }

    func testPointerPicksTheColumnUnderIt() {
        let columns = [filled(10), filled(20), filled(30), filled(40)]
        XCTAssertEqual(HistoryHover.index(x: 60, width: 100, columns: columns), 2)
        XCTAssertEqual(HistoryHover.index(x: -5, width: 100, columns: columns), 0)
        XCTAssertEqual(HistoryHover.index(x: 140, width: 100, columns: columns), 3)
    }

    func testEmptyColumnSnapsToTheNearestValue() {
        let columns = [filled(10), empty, empty, empty, filled(50)]
        XCTAssertEqual(HistoryHover.index(x: 30, width: 100, columns: columns), 0)
        XCTAssertEqual(HistoryHover.index(x: 70, width: 100, columns: columns), 4)
        XCTAssertNil(HistoryHover.index(x: 50, width: 100, columns: [empty, empty]))
    }

    func testTextShowsTimeAndBothValues() throws {
        let time = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-08T15:20:00Z"))
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let column = HistoryColumn(session: 45, weekly: 64, time: time)
        let text = HistoryHover.text(column, locale: Locale(identifier: "en_US"), timeZone: utc)
        XCTAssertEqual(text?.title, "3:20\u{202F}PM")
        XCTAssertEqual(text?.body, "Session 45%\nWeek 64%")
        XCTAssertNil(HistoryHover.text(empty))
    }
}
