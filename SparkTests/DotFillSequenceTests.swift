import XCTest
@testable import Spark

final class DotFillSequenceTests: XCTestCase {
    func testFirstOpenStartsEmptyAndEndsAtTheValue() {
        XCTAssertEqual(DotFillSequence.revealed(from: 0, to: 40, progress: 0), 0)
        XCTAssertEqual(DotFillSequence.revealed(from: 0, to: 40, progress: 0.5), 20)
        XCTAssertEqual(DotFillSequence.revealed(from: 0, to: 40, progress: 1), 40)
    }

    func testManyDotsShareTheTotalDuration() {
        // 40 dots at 25 ms each would take a second; the sequence is squeezed into 300 ms.
        XCTAssertEqual(DotFillSequence.revealed(from: 0, to: 40, progress: 0.99), 39)
    }

    func testFewDotsFollowEachOtherAt25Milliseconds() {
        // 30 ms into the fill: one stagger of 25 ms has passed.
        XCTAssertEqual(DotFillSequence.revealed(from: 10, to: 12, progress: 0.1), 11)
        XCTAssertEqual(DotFillSequence.revealed(from: 10, to: 12, progress: 0.2), 12)
    }

    func testAFallingValueShowsAtOnce() {
        XCTAssertEqual(DotFillSequence.revealed(from: 20, to: 10, progress: 0), 10)
    }

    func testProgressFollowsThePhaseToItsTarget() {
        XCTAssertEqual(DotFillSequence.progress(phase: 2, target: 3), 0, accuracy: 0.0001)
        XCTAssertEqual(DotFillSequence.progress(phase: 2.25, target: 3), 0.25, accuracy: 0.0001)
        XCTAssertEqual(DotFillSequence.progress(phase: 3, target: 3), 1, accuracy: 0.0001)
        XCTAssertEqual(DotFillSequence.progress(phase: 0, target: 0), 1, accuracy: 0.0001)
    }

    func testOnlyARisingValueFills() {
        XCTAssertEqual(DotFillSequence.start(old: 40, new: 45), 40)
        XCTAssertNil(DotFillSequence.start(old: 45, new: 45))
        XCTAssertNil(DotFillSequence.start(old: 45, new: 3))
        XCTAssertNil(DotFillSequence.start(old: .nan, new: 3))
    }

    func testFilledDotsPastTheRevealedOnesStayTrack() {
        XCTAssertEqual(DotFillSequence.dot(.filled, at: 4, revealed: 5), .filled)
        XCTAssertEqual(DotFillSequence.dot(.filled, at: 5, revealed: 5), .track)
        XCTAssertEqual(DotFillSequence.dot(.projected, at: 9, revealed: 0), .projected)
        XCTAssertEqual(DotFillSequence.dot(.track, at: 9, revealed: 0), .track)
    }

    func testLayoutCountsItsFilledDots() {
        XCTAssertEqual(DotBarLayout(count: 10, value: 45, projected: 80).filledCount, 5)
        XCTAssertEqual(DotBarLayout(count: 0, value: 45).filledCount, 0)
    }

    func testHollowDotsBreatheBetweenFullAndFaint() {
        XCTAssertEqual(DotFillSequence.projectionOpacity(breath: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(DotFillSequence.projectionOpacity(breath: 1), 0.35, accuracy: 0.0001)
    }
}
