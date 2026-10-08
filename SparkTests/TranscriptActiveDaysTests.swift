@testable import Spark
import XCTest

final class TranscriptActiveDaysTests: XCTestCase {
    private var tempDir = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("projects/-Users-me-app"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func iso(daysAgo: Int) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(TimeInterval(-daysAgo * 24 * 3600)))
    }

    private func assistant(_ id: String, input: Int, output: Int, daysAgo: Int) -> String {
        """
        {"message":{"id":"\(id)","role":"assistant","usage":{"input_tokens":\(input),"output_tokens":\(output)}},\
        "timestamp":"\(iso(daysAgo: daysAgo))","requestId":"req_\(id)"}
        """
    }

    func testActiveDaysCountOnlyDaysWithFreshTokens() throws {
        let file = tempDir.appendingPathComponent("projects/-Users-me-app/11111111-1111-1111-1111-111111111111.jsonl")
        let userOnly = #"{"message":{"role":"user"},"timestamp":"\#(iso(daysAgo: 1))"}"#
        let content = [
            assistant("a", input: 100, output: 50, daysAgo: 0),
            userOnly,
            assistant("b", input: 10, output: 5, daysAgo: 3)
        ].joined(separator: "\n") + "\n"
        try content.write(to: file, atomically: false, encoding: .utf8)
        var store = TranscriptCacheStore.empty
        let totals = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)
        XCTAssertEqual(totals.activeDays.count, 2)
    }
}
