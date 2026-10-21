@testable import Spark
import XCTest

final class SessionProjectionWindowTests: XCTestCase {
    private func snapshot(_ secondsAgo: TimeInterval, _ session: Double, now: Date) -> UsageSnapshot {
        UsageSnapshot(timestamp: now.addingTimeInterval(-secondsAgo), sessionUtilization: session, weeklyUtilization: 0)
    }

    func testIgnoresSnapshotsFromThePreviousSession() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(4.5 * 3600)
        let history = [snapshot(40 * 60, 92, now: now), snapshot(25 * 60, 2, now: now), snapshot(0, 8, now: now)]
        let result = SessionProjection.calculate(history: history, currentUtilization: 8, resetsAt: resetsAt, now: now)
        guard case .safe(let projected) = result else { return XCTFail("Expected safe, got \(result)") }
        XCTAssertEqual(projected, 8 + 6 / (25.0 / 60) * 4.5, accuracy: 0.01)
    }

    func testNeedsFifteenMinutesOfData() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(4.8 * 3600)
        let history = [snapshot(10 * 60, 2, now: now), snapshot(0, 8, now: now)]
        let result = SessionProjection.calculate(history: history, currentUtilization: 8, resetsAt: resetsAt, now: now)
        guard case .insufficientData = result else { return XCTFail("Expected insufficientData, got \(result)") }
    }

    func testUsesCodexSessionWindowRatherThanFiveHours() {
        let now = Date()
        let sessionLength: TimeInterval = 45 * 60
        let resetsAt = now.addingTimeInterval(15 * 60)
        let history = [
            snapshot(40 * 60, 95, now: now),
            snapshot(25 * 60, 5, now: now),
            snapshot(0, 10, now: now)
        ]

        let result = SessionProjection.calculate(
            history: history, currentUtilization: 10, resetsAt: resetsAt, sessionLength: sessionLength, now: now
        )

        guard case .safe(let projected) = result else { return XCTFail("Expected safe, got \(result)") }
        XCTAssertEqual(projected, 13, accuracy: 0.01)
    }

    func testIgnoresWeeklyOnlySnapshotsForSessionForecast() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let history = [
            UsageSnapshot(timestamp: now.addingTimeInterval(-20 * 60), sessionUtilization: 0, weeklyUtilization: 10, sessionMissing: true),
            UsageSnapshot(timestamp: now, sessionUtilization: 0, weeklyUtilization: 20, sessionMissing: true)
        ]

        let result = SessionProjection.calculate(
            history: history, currentUtilization: 20, resetsAt: resetsAt, sessionLength: 3 * 3600, now: now
        )

        guard case .insufficientData = result else { return XCTFail("Expected insufficient data, got \(result)") }
    }
}
