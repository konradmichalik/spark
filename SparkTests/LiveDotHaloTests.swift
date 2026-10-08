import SwiftUI
import XCTest
@testable import Spark

final class LiveDotHaloTests: XCTestCase {
    func testEveryCycleStartsSmallAndVisible() {
        XCTAssertEqual(LiveDotHalo.allCases.first, .start)
        XCTAssertEqual(LiveDotHalo.start.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(LiveDotHalo.start.opacity, 0.35, accuracy: 0.0001)
    }

    func testTheHaloGrowsFrom40To95PercentOfTheIconAndFades() {
        XCTAssertEqual(LiveDotHalo.diameter * LiveDotHalo.end.scale, 0.95, accuracy: 0.0001)
        XCTAssertEqual(LiveDotHalo.diameter, 0.4, accuracy: 0.0001)
        XCTAssertEqual(LiveDotHalo.end.opacity, 0, accuracy: 0.0001)
    }

    func testOnlyTheGrowthIsAnimatedAndTheResetSnaps() {
        XCTAssertEqual(LiveDotHalo.end.animation, .easeOut(duration: 2.4))
        XCTAssertNil(LiveDotHalo.start.animation)
    }
}

final class LiveDotHaloGateTests: XCTestCase {
    func testTheLoopWaitsForTheLayoutToSettle() {
        XCTAssertEqual(LiveDotHalo.mode(isLive: true, reduceMotion: false, isSettled: false), .still)
        XCTAssertEqual(LiveDotHalo.mode(isLive: true, reduceMotion: false, isSettled: true), .pulsing)
    }

    func testReduceMotionAndIdleNeverPulse() {
        XCTAssertEqual(LiveDotHalo.mode(isLive: true, reduceMotion: true, isSettled: true), .still)
        XCTAssertEqual(LiveDotHalo.mode(isLive: false, reduceMotion: false, isSettled: true), .hidden)
    }

    func testSettlingTakesAboutAThirdOfASecond() {
        XCTAssertEqual(LiveDotHalo.settleDelay, .milliseconds(300))
    }

    func testCancelledSettlingNeverReportsSettled() async {
        let task = Task { await LiveDotHalo.settle() }
        task.cancel()
        let settled = await task.value
        XCTAssertFalse(settled)
    }
}
