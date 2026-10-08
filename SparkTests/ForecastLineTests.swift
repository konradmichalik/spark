@testable import Spark
import XCTest

final class ForecastLineTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    private func fact(_ projection: ProjectionResult, utilization: Double = 40, toReset: TimeInterval?, elapsed: TimeInterval?) -> ForecastFact? {
        ForecastFact.make(projection: projection, utilization: utilization, secondsToReset: toReset, elapsedInWindow: elapsed, locale: english)
    }

    func testSafeForecastNamesTheValueAtReset() {
        let result = fact(.safe(79.4), utilization: 73, toReset: 3600, elapsed: 4 * 3600)
        XCTAssertEqual(result?.text, "~79% at reset")
        XCTAssertEqual(result?.tone, .normal)
        XCTAssertEqual(result?.explanation, "At ~6%/h the session ends at ~79% when it resets.")
    }

    func testCloseToTheLimitTurnsOchre() {
        XCTAssertEqual(fact(.safe(94), toReset: 3600, elapsed: 7200)?.tone, .warning)
    }

    func testForecastToneFollowsTheValueAtReset() {
        XCTAssertEqual(SessionForecast(.safe(89)).tone, .normal)
        XCTAssertEqual(SessionForecast(.safe(90)).tone, .warning)
        XCTAssertEqual(SessionForecast(.limitReached(600)).tone, .critical)
        XCTAssertEqual(SessionForecast(.insufficientData).tone, .normal)
    }

    func testLimitSaysHowEarlyItHits() {
        let result = fact(.limitReached(11_460), utilization: 16, toReset: 15_300, elapsed: 2700)
        XCTAssertEqual(result?.text, "Limit 1h 4m early")
        XCTAssertEqual(result?.tone, .critical)
        XCTAssertEqual(result?.explanation, "At ~26%/h the limit is reached in ~3h 11m, 1h 4m before the reset.")
    }

    func testLimitRightAtTheResetNamesTheTime() {
        let result = fact(.limitReached(1200), utilization: 90, toReset: 1230, elapsed: 16_000)
        XCTAssertEqual(result?.text, "Limit in ~20m")
        XCTAssertEqual(result?.explanation, "At ~30%/h the limit is reached in ~20m, around the reset.")
    }

    func testEarlySessionPromisesAForecast() {
        let early = fact(.insufficientData, toReset: 17_400, elapsed: 600)
        XCTAssertEqual(early?.text, "After 15 min")
        XCTAssertEqual(early?.explanation, "The forecast needs 15 minutes of this session's data.")
        XCTAssertNil(fact(.insufficientData, toReset: 3600, elapsed: 3600))
    }

    func testBurnRateFact() {
        XCTAssertEqual(BurnRateFact.text(25_500), "25.5K/min")
    }
}
