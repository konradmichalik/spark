@testable import Spark
import XCTest

final class HistorySpokenTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    func testNamesTheLatestSessionAndWeekValues() {
        let columns = [
            HistoryColumn(session: 10, weekly: 20),
            HistoryColumn(session: 42, weekly: 48),
            HistoryColumn(session: nil, weekly: nil)
        ]
        XCTAssertEqual(HistoryColumns.spokenLatest(columns, locale: english), "Latest: session 42%, week 48%")
    }

    func testSkipsAMissingSeries() {
        XCTAssertEqual(HistoryColumns.spokenLatest([HistoryColumn(session: nil, weekly: 30)], locale: english), "Latest: week 30%")
    }

    func testNoValuesNoText() {
        XCTAssertNil(HistoryColumns.spokenLatest([HistoryColumn(session: nil, weekly: nil)], locale: english))
        XCTAssertNil(HistoryColumns.spokenLatest([], locale: english))
    }
}
