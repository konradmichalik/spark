@testable import Spark
import XCTest

final class BarTooltipTests: XCTestCase {
    func testSessionTooltipExplainsEveryMark() {
        XCTAssertEqual(
            BarTooltip.text(window: "5-hour", showsForecast: true, elapsed: 0.54, reset: "Thursday 14:00"),
            "Share of the 5-hour limit used\nHollow dots: where the session heads at the current rate\n"
                + "Marker: 54% of the window has passed. Fill ahead of it means faster than an even pace\nResets Thursday 14:00"
        )
    }

    func testWeekTooltipWithoutForecast() {
        XCTAssertEqual(
            BarTooltip.text(window: "weekly", showsForecast: false, elapsed: 0.5, reset: nil),
            "Share of the weekly limit used\nMarker: 50% of the window has passed. Fill ahead of it means faster than an even pace"
        )
    }
}
