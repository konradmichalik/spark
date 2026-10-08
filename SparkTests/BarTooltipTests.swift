@testable import Spark
import XCTest

final class BarTooltipTests: XCTestCase {
    func testSessionTooltipExplainsEveryMark() {
        XCTAssertEqual(
            BarTooltip.text(window: "5-hour", forecast: "~79% at reset", elapsed: 0.54, reset: "Thursday 14:00"),
            "Share of the 5-hour limit used\nHollow dots: ~79% at reset\nMarker: 54% of the window has passed\nResets Thursday 14:00"
        )
    }

    func testWeekTooltipWithoutForecast() {
        XCTAssertEqual(
            BarTooltip.text(window: "weekly", forecast: nil, elapsed: 0.5, reset: nil),
            "Share of the weekly limit used\nMarker: 50% of the window has passed"
        )
    }

    func testForecastKeepsItsFurtherLines() {
        XCTAssertEqual(
            BarTooltip.text(window: "5-hour", forecast: "Limit in ~20m\n25.5K tokens per minute", elapsed: nil, reset: nil),
            "Share of the 5-hour limit used\nHollow dots: Limit in ~20m\n25.5K tokens per minute"
        )
    }

    func testAxisShowsClockTimes() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-08T15:20:00Z"))
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(
            HistoryAxis.labels(now: now, window: 6 * 3600, locale: Locale(identifier: "de_DE"), timeZone: utc),
            ["09:20", "12:20", "15:20"]
        )
    }
}
