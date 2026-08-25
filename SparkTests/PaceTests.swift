import XCTest
@testable import Spark

final class PaceTests: XCTestCase {
    private let fiveHours: TimeInterval = 5 * 3600
    private let sevenDays: TimeInterval = 7 * 24 * 3600

    func testExactlyOnPaceAtHalfway() throws {
        // Half the window elapsed, exactly half the quota used — pace should be 1.0.
        let now = Date()
        let resetsAt = now.addingTimeInterval(fiveHours / 2)

        let pace = Pace.calculate(utilization: 50, resetsAt: resetsAt, windowLength: fiveHours, now: now)

        XCTAssertEqual(try XCTUnwrap(pace).ratio, 1.0, accuracy: 0.01)
    }

    func testAheadOfBudgetWhenUtilizationOutpacesElapsedTime() throws {
        let now = Date()
        // 80% of the window remains, so 20% has elapsed; 50% utilization is well over budget.
        let resetsAt = now.addingTimeInterval(fiveHours * 0.8)

        let pace = Pace.calculate(utilization: 50, resetsAt: resetsAt, windowLength: fiveHours, now: now)

        XCTAssertEqual(try XCTUnwrap(pace).ratio, 2.5, accuracy: 0.01)
    }

    func testUnderBudgetWhenUtilizationLagsElapsedTime() throws {
        let now = Date()
        // 20% of the window remains, so 80% has elapsed; 50% utilization is comfortably under.
        let resetsAt = now.addingTimeInterval(fiveHours * 0.2)

        let pace = Pace.calculate(utilization: 50, resetsAt: resetsAt, windowLength: fiveHours, now: now)

        XCTAssertEqual(try XCTUnwrap(pace).ratio, 0.625, accuracy: 0.01)
    }

    func testStableAcrossAMultiHourPauseUnlikeLinearProjection() throws {
        // A pause changes nothing about pace — it depends only on elapsed time and current
        // utilization, never on a recent rate. Same inputs before and after a long idle period
        // yield the identical ratio, which is the point: linear projection would have collapsed
        // to "insufficient data" here since there'd be no recent-usage delta to extrapolate from.
        let now = Date()
        let resetsAt = now.addingTimeInterval(sevenDays * 0.5)

        let paceBeforePause = Pace.calculate(utilization: 40, resetsAt: resetsAt, windowLength: sevenDays, now: now)
        let paceAfterPause = Pace.calculate(
            utilization: 40,
            resetsAt: resetsAt.addingTimeInterval(3 * 3600),
            windowLength: sevenDays,
            now: now.addingTimeInterval(3 * 3600)
        )

        XCTAssertEqual(try XCTUnwrap(paceBeforePause).ratio, try XCTUnwrap(paceAfterPause).ratio, accuracy: 0.0001)
    }

    func testReturnsNilWhenResetsAtIsMissing() {
        XCTAssertNil(Pace.calculate(utilization: 50, resetsAt: nil, windowLength: fiveHours))
    }

    func testReturnsNilWhenResetsAtIsInThePast() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(-60)

        XCTAssertNil(Pace.calculate(utilization: 50, resetsAt: resetsAt, windowLength: fiveHours, now: now))
    }

    func testReturnsNilWhenResetsAtIsFartherAwayThanTheFullWindow() {
        // A stale `resetsAt` that somehow sits more than one window length in the future would
        // produce a negative or out-of-range elapsed fraction — better to show nothing than a
        // fabricated pace.
        let now = Date()
        let resetsAt = now.addingTimeInterval(fiveHours * 1.5)

        XCTAssertNil(Pace.calculate(utilization: 50, resetsAt: resetsAt, windowLength: fiveHours, now: now))
    }

    func testElapsedFractionIsExposedAlongsideTheRatio() throws {
        let now = Date()
        let resetsAt = now.addingTimeInterval(fiveHours * 0.75)

        let pace = try XCTUnwrap(Pace.calculate(utilization: 10, resetsAt: resetsAt, windowLength: fiveHours, now: now))

        XCTAssertEqual(pace.elapsedFraction, 0.25, accuracy: 0.01)
    }

    // MARK: - Tier

    func testTierIsComfortableWellBelowHalf() {
        XCTAssertEqual(Pace.Result(ratio: 0.2, elapsedFraction: 0.5).tier, .comfortable)
    }

    func testTierIsComfortableJustBelowHalf() {
        XCTAssertEqual(Pace.Result(ratio: 0.49, elapsedFraction: 0.5).tier, .comfortable)
    }

    func testTierIsOnTrackAtLowerBoundary() {
        XCTAssertEqual(Pace.Result(ratio: 0.5, elapsedFraction: 0.5).tier, .onTrack)
    }

    func testTierIsOnTrackJustBelowUpperBoundary() {
        XCTAssertEqual(Pace.Result(ratio: 0.74, elapsedFraction: 0.5).tier, .onTrack)
    }

    func testTierIsWarmingAtLowerBoundary() {
        XCTAssertEqual(Pace.Result(ratio: 0.75, elapsedFraction: 0.5).tier, .warming)
    }

    func testTierIsWarmingJustBelowUpperBoundary() {
        XCTAssertEqual(Pace.Result(ratio: 0.89, elapsedFraction: 0.5).tier, .warming)
    }

    func testTierIsPressingAtLowerBoundary() {
        XCTAssertEqual(Pace.Result(ratio: 0.9, elapsedFraction: 0.5).tier, .pressing)
    }

    func testTierIsPressingJustBelowUpperBoundary() {
        XCTAssertEqual(Pace.Result(ratio: 0.99, elapsedFraction: 0.5).tier, .pressing)
    }

    func testTierIsCriticalAtLowerBoundary() {
        XCTAssertEqual(Pace.Result(ratio: 1.0, elapsedFraction: 0.5).tier, .critical)
    }

    func testTierIsCriticalJustBelowUpperBoundary() {
        XCTAssertEqual(Pace.Result(ratio: 1.19, elapsedFraction: 0.5).tier, .critical)
    }

    func testTierIsRunawayAtLowerBoundary() {
        XCTAssertEqual(Pace.Result(ratio: 1.2, elapsedFraction: 0.5).tier, .runaway)
    }

    func testTierIsRunawayWellAboveBoundary() {
        XCTAssertEqual(Pace.Result(ratio: 3.0, elapsedFraction: 0.5).tier, .runaway)
    }
}
