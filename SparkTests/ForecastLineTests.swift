@testable import Spark
import XCTest

final class ForecastLineTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    func testSafeForecastNamesTheValueAtReset() {
        let line = ForecastLine.make(projection: .safe(79.4), secondsToReset: 3600, elapsedInWindow: 7200, locale: english)
        XCTAssertEqual(line, ForecastLine(text: "~79% at reset", isWarning: false))
    }

    func testLimitSaysHowLongBeforeTheReset() {
        let line = ForecastLine.make(projection: .limitReached(7440), secondsToReset: 17_400, elapsedInWindow: 600, locale: english)
        XCTAssertEqual(line, ForecastLine(text: "Limit in ~2h 4m \u{00B7} 2h 46m before reset", isWarning: true))
    }

    func testLimitRightAtTheResetDropsTheGap() {
        let line = ForecastLine.make(projection: .limitReached(1200), secondsToReset: 1230, elapsedInWindow: 16_000, locale: english)
        XCTAssertEqual(line, ForecastLine(text: "Limit in ~20m", isWarning: true))
    }

    func testEarlySessionPromisesAForecast() {
        let early = ForecastLine.make(projection: .insufficientData, secondsToReset: 17_400, elapsedInWindow: 600, locale: english)
        XCTAssertEqual(early, ForecastLine(text: "Forecast after 15 min", isWarning: false))
        XCTAssertNil(ForecastLine.make(projection: .insufficientData, secondsToReset: 3600, elapsedInWindow: 3600, locale: english))
    }
}
