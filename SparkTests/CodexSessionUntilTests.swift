@testable import Spark
import XCTest

final class CodexSessionUntilTests: XCTestCase {
    func testEventsAfterTheUpperBoundAreIgnored() throws {
        func event(_ time: String, input: Int) -> String {
            """
            {"timestamp":"\(time)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":\
            {"input_tokens":\(input),"cached_input_tokens":0,"output_tokens":0}}}}
            """
        }
        let content = [event("2026-10-05T10:00:00.000Z", input: 100), event("2026-10-09T10:00:00.000Z", input: 250)].joined(separator: "\n")
        let formatter = ISO8601DateFormatter()
        let since = try XCTUnwrap(formatter.date(from: "2026-10-01T00:00:00Z"))
        let until = try XCTUnwrap(formatter.date(from: "2026-10-07T00:00:00Z"))
        XCTAssertEqual(CodexSessionStats.parseFile(content: content, since: since, until: until).realTokens, 100)
        XCTAssertEqual(CodexSessionStats.parseFile(content: content, since: since).realTokens, 250)
    }
}
