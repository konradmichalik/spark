import XCTest
@testable import Spark

final class CodexSessionStatsTests: XCTestCase {
    private var tempDir = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func writeRollout(_ name: String, in subdir: String = "2026/10/07", lines: [String]) throws -> URL {
        let dir = tempDir.appendingPathComponent(subdir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data(lines.joined(separator: "\n").utf8).write(to: url)
        return url
    }

    private func tokenCount(_ time: String, input: Int, cached: Int, output: Int, reasoning: Int = 0) -> String {
        """
        {"timestamp":"\(time)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":\
        {"input_tokens":\(input),"cached_input_tokens":\(cached),"output_tokens":\(output),"reasoning_output_tokens":\(reasoning),\
        "total_tokens":\(input + output)},"last_token_usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0,\
        "reasoning_output_tokens":0,"total_tokens":0},"model_context_window":272000},"rate_limits":null}}
        """
    }

    private func userMessage(_ time: String) -> String {
        #"{"timestamp":"\#(time)","type":"event_msg","payload":{"type":"user_message","message":"hi token_count"}}"#
    }

    private func turnContext(_ time: String, model: String) -> String {
        #"{"timestamp":"\#(time)","type":"turn_context","payload":{"cwd":"/tmp","model":"\#(model)","effort":"high"}}"#
    }

    private func date(_ iso: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: iso))
    }

    func testSumsCumulativeTotalsAsDeltas() throws {
        _ = try writeRollout("rollout-a.jsonl", lines: [
            #"{"timestamp":"2026-10-07T08:00:00.000Z","type":"session_meta","payload":{"id":"a","cwd":"/tmp"}}"#,
            turnContext("2026-10-07T08:00:01.000Z", model: "gpt-5.5-codex"),
            userMessage("2026-10-07T08:00:02.000Z"),
            tokenCount("2026-10-07T08:00:10.000Z", input: 1000, cached: 400, output: 200, reasoning: 50),
            // Re-emitted with unchanged totals (rate limit update): must not count twice.
            tokenCount("2026-10-07T08:00:11.000Z", input: 1000, cached: 400, output: 200, reasoning: 50),
            userMessage("2026-10-07T08:01:00.000Z"),
            tokenCount("2026-10-07T08:01:10.000Z", input: 3000, cached: 1400, output: 500, reasoning: 80)
        ])

        let stats = CodexSessionStats.parse(directories: [tempDir], since: nil)

        XCTAssertEqual(stats.sessionCount, 1)
        XCTAssertEqual(stats.messageCount, 2)
        XCTAssertEqual(stats.inputTokens, 1600, "input_tokens includes cached tokens, so only 3000 - 1400 is fresh")
        XCTAssertEqual(stats.cachedInputTokens, 1400)
        XCTAssertEqual(stats.outputTokens, 500)
        XCTAssertEqual(stats.reasoningTokens, 80)
        XCTAssertEqual(stats.totalTokens, 3500)
        XCTAssertEqual(stats.modelTokens, ["gpt-5.5-codex": 3500])
        XCTAssertEqual(stats.fileCount, 1)
    }

    /// A session resumed today counts only what happened since the cutoff, not its whole history.
    func testOnlyCountsActivityAfterCutoff() throws {
        _ = try writeRollout("rollout-b.jsonl", in: "2026/10/05", lines: [
            turnContext("2026-10-05T10:00:00.000Z", model: "gpt-5.5"),
            userMessage("2026-10-05T10:00:01.000Z"),
            tokenCount("2026-10-05T10:00:10.000Z", input: 1000, cached: 0, output: 100),
            userMessage("2026-10-07T09:00:00.000Z"),
            tokenCount("2026-10-07T09:00:10.000Z", input: 1500, cached: 0, output: 300)
        ])

        let stats = CodexSessionStats.parse(directories: [tempDir], since: try date("2026-10-07T00:00:00Z"))

        XCTAssertEqual(stats.sessionCount, 1)
        XCTAssertEqual(stats.messageCount, 1)
        XCTAssertEqual(stats.inputTokens, 500)
        XCTAssertEqual(stats.outputTokens, 200)
    }

    func testFilesWithoutActivityInPeriodAreNotSessions() throws {
        _ = try writeRollout("rollout-old.jsonl", in: "2026/09/01", lines: [
            userMessage("2026-09-01T10:00:00.000Z"),
            tokenCount("2026-09-01T10:00:10.000Z", input: 10, cached: 0, output: 1)
        ])

        let stats = CodexSessionStats.parse(directories: [tempDir], since: try date("2026-10-07T00:00:00Z"))

        XCTAssertEqual(stats.sessionCount, 0)
        XCTAssertEqual(stats.totalTokens, 0)
        XCTAssertEqual(stats.fileCount, 1)
    }

    func testModelSwitchAttributesTokensPerModel() throws {
        _ = try writeRollout("rollout-c.jsonl", lines: [
            turnContext("2026-10-07T08:00:00.000Z", model: "gpt-5.5"),
            tokenCount("2026-10-07T08:00:10.000Z", input: 100, cached: 0, output: 10),
            turnContext("2026-10-07T08:05:00.000Z", model: "gpt-5.5-mini"),
            tokenCount("2026-10-07T08:05:10.000Z", input: 300, cached: 0, output: 20)
        ])

        let stats = CodexSessionStats.parse(directories: [tempDir], since: nil)

        XCTAssertEqual(stats.modelTokens, ["gpt-5.5": 110, "gpt-5.5-mini": 210])
    }

    func testSkipsMalformedLinesCompressedAndForeignFiles() throws {
        _ = try writeRollout("rollout-d.jsonl", lines: [
            "not json at all",
            #"{"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":null}}"#,
            userMessage("2026-10-07T08:00:00.000Z"),
            "{\"truncated\":"
        ])
        _ = try writeRollout("rollout-e.jsonl.zst", lines: ["binary"])
        _ = try writeRollout("notes.txt", lines: [userMessage("2026-10-07T08:00:00.000Z")])

        let stats = CodexSessionStats.parse(directories: [tempDir], since: nil)

        XCTAssertEqual(stats.fileCount, 1)
        XCTAssertEqual(stats.sessionCount, 1)
        XCTAssertEqual(stats.messageCount, 1)
        XCTAssertEqual(stats.totalTokens, 0)
    }

    func testMissingDirectoryYieldsEmptyStats() {
        let stats = CodexSessionStats.parse(directories: [tempDir.appendingPathComponent("missing")], since: nil)

        XCTAssertEqual(stats, CodexSessionStats())
    }
}
