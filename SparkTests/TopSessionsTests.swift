import XCTest
@testable import Spark

final class TopSessionsTests: XCTestCase {
    private let sessionId = "11111111-1111-1111-1111-111111111111"
    private var tempDir = FileManager.default.temporaryDirectory
    private var projectDir = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        projectDir = tempDir.appendingPathComponent("projects/-Users-me-app")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func date(daysAgo: Int, hour: Int) -> Date {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    private func line(id: String, input: Int, at date: Date) -> String {
        """
        {"message":{"id":"\(id)","role":"assistant","model":"claude-opus-5",\
        "usage":{"input_tokens":\(input),"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":500}},\
        "timestamp":"\(ISO8601DateFormatter().string(from: date))","requestId":"req_\(id)"}
        """
    }

    private func write(_ lines: [String], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: false, encoding: .utf8)
    }

    private func aggregate(cutoff: Date? = nil) -> TranscriptTotals {
        var store = TranscriptCacheStore.empty
        return TranscriptCache.aggregate(claudeDir: tempDir, cutoff: cutoff, store: &store)
    }

    // MARK: - Aggregation

    func testSubagentTranscriptsCountTowardTheirParentSession() throws {
        let start = date(daysAgo: 0, hour: 9)
        let end = date(daysAgo: 0, hour: 11)
        try write([line(id: "a", input: 100, at: start)], to: projectDir.appendingPathComponent("\(sessionId).jsonl"))
        try write(
            [line(id: "b", input: 40, at: end)],
            to: projectDir.appendingPathComponent("\(sessionId)/subagents/agent-1.jsonl")
        )

        let session = try XCTUnwrap(aggregate().sessionTotals[sessionId])

        XCTAssertEqual(session.projectKey, "-Users-me-app")
        XCTAssertEqual(session.real, 140, "cache reads are left out, like Top Projects")
        XCTAssertEqual(session.modelTotals["claude-opus-5"]?.input, 140)
        XCTAssertEqual(session.activity?.first.timeIntervalSince1970 ?? 0, start.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(session.activity?.last.timeIntervalSince1970 ?? 0, end.timeIntervalSince1970, accuracy: 1)
    }

    func testTokensAreClippedToThePeriodButActivitySpansTheWholeSession() throws {
        let start = date(daysAgo: 10, hour: 9)
        try write(
            [line(id: "old", input: 1_000, at: start), line(id: "new", input: 7, at: date(daysAgo: 0, hour: 9))],
            to: projectDir.appendingPathComponent("\(sessionId).jsonl")
        )

        let session = try XCTUnwrap(aggregate(cutoff: date(daysAgo: 2, hour: 0)).sessionTotals[sessionId])

        XCTAssertEqual(session.real, 7)
        XCTAssertEqual(session.activity?.first.timeIntervalSince1970 ?? 0, start.timeIntervalSince1970, accuracy: 1)
    }

    func testSessionsWithoutActivityInThePeriodAreLeftOut() throws {
        try write([line(id: "old", input: 1_000, at: date(daysAgo: 10, hour: 9))], to: projectDir.appendingPathComponent("\(sessionId).jsonl"))

        XCTAssertNil(aggregate(cutoff: date(daysAgo: 2, hour: 0)).sessionTotals[sessionId])
    }

    func testAppendedLinesExtendTheActivitySpan() throws {
        let fileURL = projectDir.appendingPathComponent("\(sessionId).jsonl")
        let start = date(daysAgo: 0, hour: 9)
        let later = date(daysAgo: 0, hour: 12)
        try write([line(id: "a", input: 1, at: start)], to: fileURL)
        var store = TranscriptCacheStore.empty
        _ = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)

        let handle = try FileHandle(forWritingTo: fileURL)
        handle.seekToEndOfFile()
        handle.write(Data((line(id: "b", input: 1, at: later) + "\n").utf8))
        try handle.close()
        let totals = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)

        let activity = try XCTUnwrap(totals.sessionTotals[sessionId]?.activity)
        XCTAssertEqual(activity.first.timeIntervalSince1970, start.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(activity.last.timeIntervalSince1970, later.timeIntervalSince1970, accuracy: 1)
    }

    // MARK: - Ranking

    func testTopSessionsRankByRealTokensAndSkipEmptyOnes() {
        let span = ActivitySpan(first: Date(timeIntervalSince1970: 0), last: Date(timeIntervalSince1970: 3_600))
        let stats = LiveStats(
            period: .week,
            messageCount: 1,
            sessionCount: 3,
            inputTokens: 0,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            projectDisplayNames: ["-Users-me-app": "/Users/me/app"],
            sessionTotals: [
                "small": SessionTotals(projectKey: "-Users-me-app", real: 10, activity: span),
                "big": SessionTotals(projectKey: "-Users-me-app", real: 500, activity: span),
                "empty": SessionTotals(projectKey: "-Users-me-app", real: 0, activity: span)
            ]
        )

        let top = stats.topSessions(limit: 5)

        XCTAssertEqual(top.map(\.id), ["big", "small"])
        XCTAssertEqual(top.first?.displayName, ProjectFamily.displayName(forKey: "-Users-me-app", cwd: "/Users/me/app"))
        XCTAssertEqual(top.first?.duration, 3_600)
        XCTAssertEqual(stats.topSessions(limit: 1).map(\.id), ["big"])
    }

    // MARK: - Cost

    func testSummaryPricesEachSession() throws {
        let table = PricingTable(prices: [
            "claude-opus-5": ModelPrice(input: 1e-6, output: 0, cacheCreation: 0, cacheCreation1h: 0, cacheRead: 0)
        ])
        let million = ModelTokenTotals(input: 1_000_000, output: 0, cacheCreation: 0, cacheRead: 0)

        let summary = table.summary(
            modelTotals: ["claude-opus-5": million],
            projectModelTotals: [:],
            sessionModelTotals: ["s1": ["claude-opus-5": million]]
        )

        XCTAssertEqual(try XCTUnwrap(summary.bySession["s1"]), 1.0, accuracy: 1e-9)
    }
}
