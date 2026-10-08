@testable import Spark
import XCTest

final class DayTokensTests: XCTestCase {
    private var tempDir = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("projects/-Users-me-app"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testCodexDayTokensCountFreshTokensPerDay() throws {
        func event(_ time: String, input: Int, cached: Int, output: Int) -> String {
            """
            {"timestamp":"\(time)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":\
            {"input_tokens":\(input),"cached_input_tokens":\(cached),"output_tokens":\(output)}}}}
            """
        }
        let content = [
            event("2026-10-05T10:00:00.000Z", input: 1000, cached: 400, output: 100),
            event("2026-10-05T10:00:01.000Z", input: 1000, cached: 400, output: 100),
            event("2026-10-07T10:00:00.000Z", input: 1500, cached: 400, output: 150)
        ].joined(separator: "\n")
        let stats = CodexSessionStats.parseFile(content: content, since: nil)
        let first = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-05T10:00:00Z").map { TranscriptCache.dayKey(for: $0) })
        XCTAssertEqual(stats.dayTokens.values.reduce(0, +), stats.realTokens)
        XCTAssertEqual(stats.dayTokens.count, 2)
        XCTAssertEqual(stats.dayTokens[first], 700, "600 fresh input and 100 output, the re-emitted event adds nothing")
        XCTAssertEqual(stats.activeDayCount, stats.dayTokens.count)
    }

    func testClaudeTotalsKeepFreshTokensPerDay() throws {
        let file = tempDir.appendingPathComponent("projects/-Users-me-app/11111111-1111-1111-1111-111111111111.jsonl")
        func line(_ id: String, input: Int, output: Int, daysAgo: Int) -> String {
            let stamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(TimeInterval(-daysAgo * 24 * 3600)))
            return """
            {"message":{"id":"\(id)","role":"assistant","usage":{"input_tokens":\(input),"output_tokens":\(output)}},\
            "timestamp":"\(stamp)","requestId":"req_\(id)"}
            """
        }
        let content = [line("a", input: 100, output: 50, daysAgo: 0), line("b", input: 10, output: 5, daysAgo: 3)].joined(separator: "\n") + "\n"
        try content.write(to: file, atomically: false, encoding: .utf8)
        var store = TranscriptCacheStore.empty
        let totals = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)
        XCTAssertEqual(totals.dayTokens[TranscriptCache.dayKey(for: Date())], 150)
        XCTAssertEqual(totals.dayTokens.values.reduce(0, +), 165)
        XCTAssertEqual(totals.activeDayCount, 2)
    }
}
