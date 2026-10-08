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

    func testTheBaseLayerNeverDrawsHollowDots() {
        let layout = DotBarLayout(count: 10, value: 30, projected: 60)
        let base = DotBarLayout.baseDots(layout.dots)
        XCTAssertEqual(base.filter { $0 == .projected }.count, 0)
        XCTAssertEqual(base.filter { $0 == .filled }.count, 3)
        XCTAssertEqual(base.count, layout.dots.count)
    }

    func testBreathingNeedsAnActiveSettledLayerWithMotionAllowed() {
        XCTAssertTrue(DotFillSequence.shouldBreathe(isActive: true, reduceMotion: false, isSettled: true))
        XCTAssertFalse(DotFillSequence.shouldBreathe(isActive: false, reduceMotion: false, isSettled: true))
        XCTAssertFalse(DotFillSequence.shouldBreathe(isActive: true, reduceMotion: true, isSettled: true))
        XCTAssertFalse(DotFillSequence.shouldBreathe(isActive: true, reduceMotion: false, isSettled: false))
    }
}
