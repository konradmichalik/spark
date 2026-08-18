import XCTest
@testable import Spark

final class SessionDiscoveryTests: XCTestCase {

    // MARK: - Pure path -> session ID derivation

    func testSessionFileStemIsItsOwnSessionId() {
        let projectsDir = URL(fileURLWithPath: "/home/.claude/projects")
        let transcript = projectsDir
            .appendingPathComponent("-Users-me-app")
            .appendingPathComponent("11111111-1111-1111-1111-111111111111.jsonl")

        XCTAssertEqual(
            LiveStatsParser.sessionId(forTranscriptAt: transcript, projectsDir: projectsDir),
            "11111111-1111-1111-1111-111111111111"
        )
    }

    func testSubagentTranscriptResolvesToParentSessionDirectory() {
        let projectsDir = URL(fileURLWithPath: "/home/.claude/projects")
        let transcript = projectsDir
            .appendingPathComponent("-Users-me-app")
            .appendingPathComponent("11111111-1111-1111-1111-111111111111")
            .appendingPathComponent("subagents")
            .appendingPathComponent("agent-a3ce07909d658440e.jsonl")

        XCTAssertEqual(
            LiveStatsParser.sessionId(forTranscriptAt: transcript, projectsDir: projectsDir),
            "11111111-1111-1111-1111-111111111111"
        )
    }

    func testUnrecognizedPathShapeReturnsNil() {
        let projectsDir = URL(fileURLWithPath: "/home/.claude/projects")
        let transcript = projectsDir.appendingPathComponent("orphan.jsonl")

        XCTAssertNil(LiveStatsParser.sessionId(forTranscriptAt: transcript, projectsDir: projectsDir))
    }

    // MARK: - Full scan against a real fixture tree

    private var tempClaudeDir = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        tempClaudeDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempClaudeDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempClaudeDir)
    }

    private func write(_ content: String, to relativePath: String) throws {
        let url = tempClaudeDir.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func assistantLine(sessionId: String, input: Int, output: Int) -> String {
        """
        {"message":{"role":"assistant","usage":{"input_tokens":\(input),"output_tokens":\(output)}},\
        "timestamp":"2026-01-01T00:00:00Z","sessionId":"\(sessionId)"}
        """
    }

    func testSubagentTranscriptTokensAreIncludedAndAttributedToParentSession() throws {
        let sessionId = "11111111-1111-1111-1111-111111111111"
        try write(
            assistantLine(sessionId: sessionId, input: 100, output: 50),
            to: "projects/-Users-me-app/\(sessionId).jsonl"
        )
        try write(
            assistantLine(sessionId: sessionId, input: 10, output: 5),
            to: "projects/-Users-me-app/\(sessionId)/subagents/agent-abc123.jsonl"
        )

        let stats = try XCTUnwrap(LiveStatsParser.parseStats(period: .all, claudeDir: tempClaudeDir))

        XCTAssertEqual(stats.inputTokens, 110)
        XCTAssertEqual(stats.outputTokens, 55)
        XCTAssertEqual(stats.sessionCount, 1, "subagent tokens must attribute to the parent session, not a second session")
    }

    func testSessionsWithoutAHistoryEntryAreStillCounted() throws {
        let sessionId = "22222222-2222-2222-2222-222222222222"
        try write("", to: "history.jsonl")
        try write(
            assistantLine(sessionId: sessionId, input: 42, output: 7),
            to: "projects/-Users-me-app/\(sessionId).jsonl"
        )

        let stats = try XCTUnwrap(LiveStatsParser.parseStats(period: .all, claudeDir: tempClaudeDir))

        XCTAssertEqual(stats.inputTokens, 42)
        XCTAssertEqual(stats.sessionCount, 1)
    }

    func testStatsAreProducedWhenHistoryFileIsAbsent() throws {
        let sessionId = "33333333-3333-3333-3333-333333333333"
        try write(
            assistantLine(sessionId: sessionId, input: 10, output: 1),
            to: "projects/-Users-me-app/\(sessionId).jsonl"
        )
        // No history.jsonl written at all.

        let stats = LiveStatsParser.parseStats(period: .all, claudeDir: tempClaudeDir)

        XCTAssertNotNil(stats)
        XCTAssertEqual(stats?.inputTokens, 10)
    }

    func testNoStatsWhenNeitherHistoryNorTranscriptsExist() {
        let stats = LiveStatsParser.parseStats(period: .all, claudeDir: tempClaudeDir)
        XCTAssertNil(stats)
    }

    func testPathBasedSessionIdResolvesWithoutAnySessionIdFallbackInTheEntry() throws {
        // Regression test: `tempClaudeDir` lives under the real temp directory, which on macOS
        // is reached through the `/var` -> `/private/var` symlink. `FileManager.enumerator`
        // yields fully symlink-resolved paths while a naively-constructed `projectsDir` does
        // not, so component-count-based path math silently breaks unless both sides are
        // resolved consistently. This fixture has no `sessionId` JSON field, so a broken
        // path resolution surfaces as a dropped entry (nil stats) rather than being masked by
        // the fallback the other tests in this file rely on.
        let sessionId = "55555555-5555-5555-5555-555555555555"
        try write(
            """
            {"message":{"role":"assistant","usage":{"input_tokens":9,"output_tokens":1}},\
            "timestamp":"2026-01-01T00:00:00Z"}
            """,
            to: "projects/-Users-me-app/\(sessionId).jsonl"
        )

        let stats = try XCTUnwrap(LiveStatsParser.parseStats(period: .all, claudeDir: tempClaudeDir))

        XCTAssertEqual(stats.inputTokens, 9)
        XCTAssertEqual(stats.sessionCount, 1)
    }

    func testSessionWithOnlyUserRecordsIsStillCounted() throws {
        // Regression test: session-ID resolution must not be gated behind the same guard as
        // token aggregation. A transcript containing only a user message (no assistant record,
        // no usage) is still a real session and must be counted, even though it contributes no
        // tokens.
        let sessionId = "66666666-6666-6666-6666-666666666666"
        try write(
            """
            {"message":{"role":"user"},"timestamp":"2026-01-01T00:00:00Z","sessionId":"\(sessionId)"}
            """,
            to: "projects/-Users-me-app/\(sessionId).jsonl"
        )

        let stats = try XCTUnwrap(LiveStatsParser.parseStats(period: .all, claudeDir: tempClaudeDir))

        XCTAssertEqual(stats.sessionCount, 1)
        XCTAssertEqual(stats.inputTokens, 0)
        XCTAssertEqual(stats.outputTokens, 0)
    }

    func testAssistantRecordWithoutUsageStillCountsItsSession() throws {
        // Regression test: an assistant message that hasn't finished streaming (or otherwise
        // lacks a `usage` field) must not exclude its session from the session count, even
        // though it contributes no tokens.
        let sessionId = "77777777-7777-7777-7777-777777777777"
        try write(
            """
            {"message":{"role":"assistant"},"timestamp":"2026-01-01T00:00:00Z","sessionId":"\(sessionId)"}
            """,
            to: "projects/-Users-me-app/\(sessionId).jsonl"
        )

        let stats = try XCTUnwrap(LiveStatsParser.parseStats(period: .all, claudeDir: tempClaudeDir))

        XCTAssertEqual(stats.sessionCount, 1)
        XCTAssertEqual(stats.inputTokens, 0)
        XCTAssertEqual(stats.outputTokens, 0)
    }

    func testOrphanedTranscriptFallsBackToEntrySessionIdField() throws {
        // A path shape the depth-based resolver doesn't recognise (directly under `projects/`,
        // no project directory). The scan must still count it using the entry's own `sessionId`.
        let sessionId = "44444444-4444-4444-4444-444444444444"
        try write(
            assistantLine(sessionId: sessionId, input: 5, output: 5),
            to: "projects/orphan.jsonl"
        )

        let stats = try XCTUnwrap(LiveStatsParser.parseStats(period: .all, claudeDir: tempClaudeDir))

        XCTAssertEqual(stats.inputTokens, 5)
        XCTAssertEqual(stats.sessionCount, 1)
    }
}
