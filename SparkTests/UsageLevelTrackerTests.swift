import XCTest
@testable import Spark

final class UsageLevelTrackerTests: XCTestCase {
    private func update(
        _ tracker: inout UsageLevelTracker, session: Double, week: Double
    ) -> [UsageLevelTracker.Crossing] {
        tracker.update([("Session", session), ("Week", week)], warning: 75, critical: 90)
    }

    func testReportsEachWindowThatCrossedIntoALevel() {
        var tracker = UsageLevelTracker()
        let crossings = update(&tracker, session: 80, week: 95)
        XCTAssertEqual(crossings.map(\.key), ["Session", "Week"])
        XCTAssertEqual(crossings.map(\.level), [.warning, .critical])
    }

    /// The week stays at 85% (already notified) while the session rises: the maximum does not move.
    func testSessionRiseIsReportedWhileTheWeekStaysPut() {
        var tracker = UsageLevelTracker()
        XCTAssertEqual(update(&tracker, session: 60, week: 85).map(\.key), ["Week"])
        let crossings = update(&tracker, session: 80, week: 85)
        XCTAssertEqual(crossings.map(\.key), ["Session"])
        XCTAssertEqual(crossings.first?.level, .warning)
    }

    func testSameLevelIsNotReportedTwiceAndFallingBackRearms() {
        var tracker = UsageLevelTracker()
        XCTAssertEqual(update(&tracker, session: 80, week: 10).count, 1)
        XCTAssertTrue(update(&tracker, session: 82, week: 10).isEmpty)
        XCTAssertTrue(update(&tracker, session: 10, week: 10).isEmpty)
        XCTAssertEqual(update(&tracker, session: 80, week: 10).count, 1)
    }

    func testEscalationFromWarningToCriticalIsReported() {
        var tracker = UsageLevelTracker()
        _ = update(&tracker, session: 80, week: 10)
        XCTAssertEqual(update(&tracker, session: 95, week: 10).first?.level, .critical)
    }

    /// Codex windows can share a label, so they are keyed by their own id.
    func testWindowsWithTheSameLabelAreTrackedSeparately() {
        var tracker = UsageLevelTracker()
        let first = tracker.update([("0-Max", 95), ("1-Max", 10)], warning: 75, critical: 90)
        XCTAssertEqual(first.map(\.key), ["0-Max"])
        let second = tracker.update([("0-Max", 95), ("1-Max", 80)], warning: 75, critical: 90)
        XCTAssertEqual(second.map(\.key), ["1-Max"])
    }
}
