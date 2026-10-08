@testable import Spark
import XCTest

final class LimitLineIdTests: XCTestCase {
    func testCodexWindowsWithTheSameLabelGetDistinctIds() throws {
        let json = """
        {"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":41,"limit_window_seconds":18000}},
        "additional_rate_limits":[
        {"limit_name":"Max","rate_limit":{"primary_window":{"used_percent":95,"limit_window_seconds":2592000}}},
        {"limit_name":"Max","rate_limit":{"primary_window":{"used_percent":10,"limit_window_seconds":2592000}}}]}
        """
        let response = try JSONDecoder().decode(CodexUsageResponse.self, from: Data(json.utf8))
        let sections = AllLimits.codex(CodexUsage(response: response), warning: 75, critical: 90)
        XCTAssertEqual(sections.limits.count, 2)
        XCTAssertEqual(Set(sections.limits.map(\.id)).count, 2)
    }

    func testLinesWithoutAKeyUseTheirLabel() {
        XCTAssertEqual(LimitLine(label: "Credits", value: nil, tone: .normal).id, "Credits")
    }
}
