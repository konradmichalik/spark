@testable import Spark
import XCTest

final class HeadlineLimitTests: XCTestCase {
    private func bucket(_ value: Double) -> UsageBucket {
        UsageBucket(utilization: value, resetsAt: nil)
    }

    private func named(_ label: String, _ value: Double) -> CodexNamedLimit {
        CodexNamedLimit(label: label, bucket: bucket(value), windowSeconds: 30 * 86_400, position: 0)
    }

    func testWeekLeadsWhenThereIsNoSession() {
        let headline = HeadlineLimit.withoutSession(weekly: bucket(40), others: [named("30 days", 10)])
        XCTAssertEqual(headline?.label, "WEEK")
        XCTAssertEqual(headline?.bucket.utilization, 40)
        XCTAssertEqual(headline?.window, 7 * 86_400)
    }

    func testFirstOtherLimitLeadsWithoutWeek() {
        let headline = HeadlineLimit.withoutSession(weekly: nil, others: [named("30 days", 12), named("Daily", 3)])
        XCTAssertEqual(headline?.label, "30 DAYS")
        XCTAssertEqual(headline?.bucket.utilization, 12)
        XCTAssertEqual(headline?.window, 30 * 86_400)
    }

    func testNothingLeadsWithoutAnyLimit() {
        XCTAssertNil(HeadlineLimit.withoutSession(weekly: nil, others: []))
    }

    func testEmptyTextNamesAReachedLimit() {
        XCTAssertEqual(HeadlineLimit.emptyText(limitReached: true), "Usage limit reached")
        XCTAssertEqual(HeadlineLimit.emptyText(limitReached: false), "No limits reported for this plan")
    }

    func testAccessibilityValueAddsTheForecast() {
        let english = Locale(identifier: "en_US")
        XCTAssertEqual(HeadlineLimit.accessibilityValue(45, detail: "~79% at reset", locale: english), "45%. ~79% at reset")
        XCTAssertEqual(HeadlineLimit.accessibilityValue(45, detail: nil, locale: english), "45%")
    }
}
