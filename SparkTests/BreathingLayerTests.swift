@testable import Spark
import XCTest

final class BreathingLayerTests: XCTestCase {
    func testOnlyTheHollowDotsLiveInTheBreathingLayer() {
        let layout = DotBarLayout(count: 10, value: 30, projected: 60)
        XCTAssertEqual(layout.projectedPositions, [3, 4, 5])
    }

    func testNoProjectionMeansNothingBreathes() {
        XCTAssertEqual(DotBarLayout(count: 10, value: 30).projectedPositions, [])
        XCTAssertEqual(DotBarLayout(count: 10, value: 60, projected: 40).projectedPositions, [])
    }

    func testTheBaseLayerLeavesTheHollowDotsEmpty() {
        let layout = DotBarLayout(count: 10, value: 30, projected: 60)
        let base = DotBarLayout.baseDots(layout.dots)
        XCTAssertEqual(base.count, layout.dots.count)
        // Nothing sits under a hollow dot, so its centre stays empty.
        XCTAssertEqual(base[3], nil)
        XCTAssertEqual(base[4], nil)
        XCTAssertEqual(base[5], nil)
        XCTAssertEqual(base.compactMap { $0 }.filter { $0 == .filled }.count, 3)
        XCTAssertEqual(base.compactMap { $0 }.filter { $0 == .track }.count, 4)
    }

    func testAFillInProgressKeepsTrackDotsForUnrevealedPositions() {
        let layout = DotBarLayout(count: 10, value: 30, projected: 60)
        let unrevealed = layout.dots.enumerated().map { DotFillSequence.dot($1, at: $0, revealed: 1) }
        let base = DotBarLayout.baseDots(unrevealed)
        XCTAssertEqual(base[0], .filled)
        XCTAssertEqual(base[1], .track)
        XCTAssertEqual(base[2], .track)
        XCTAssertEqual(base[3], nil)
    }

    func testBreathingNeedsAnActiveSettledLayerWithMotionAllowed() {
        XCTAssertTrue(DotFillSequence.shouldBreathe(isActive: true, reduceMotion: false, isSettled: true))
        XCTAssertFalse(DotFillSequence.shouldBreathe(isActive: false, reduceMotion: false, isSettled: true))
        XCTAssertFalse(DotFillSequence.shouldBreathe(isActive: true, reduceMotion: true, isSettled: true))
        XCTAssertFalse(DotFillSequence.shouldBreathe(isActive: true, reduceMotion: false, isSettled: false))
    }
}
