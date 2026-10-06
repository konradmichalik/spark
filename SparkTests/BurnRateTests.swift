import XCTest
@testable import Spark

final class BurnRateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func file(_ turns: [TurnSample]) -> FileParseCache {
        FileParseCache(mtime: now, size: 10, parsedByteOffset: 10, dailyBuckets: [:], recentTurns: turns)
    }

    private func turn(minutesAgo: Double, tokens: Int) -> TurnSample {
        TurnSample(date: now.addingTimeInterval(-minutesAgo * 60), tokens: tokens)
    }

    // MARK: - calculate

    func testNoTurnsMeansNoBurnRate() {
        XCTAssertNil(BurnRate.calculate(files: [file([])], now: now))
    }

    func testTurnsOlderThanTheWindowMeanNoBurnRate() {
        XCTAssertNil(BurnRate.calculate(files: [file([turn(minutesAgo: 16, tokens: 90_000)])], now: now))
    }

    func testAveragesTurnsAcrossFilesOverTheWholeWindow() throws {
        let files = [
            file([turn(minutesAgo: 1, tokens: 150_000), turn(minutesAgo: 20, tokens: 1_000_000)]),
            file([turn(minutesAgo: 14, tokens: 150_000)])
        ]

        let rate = try XCTUnwrap(BurnRate.calculate(files: files, now: now))

        XCTAssertEqual(rate.tokensPerMinute, 20_000)
    }

    func testTierBoundaries() {
        XCTAssertEqual(BurnRate(tokensPerMinute: 19_999).tier, .normal)
        XCTAssertEqual(BurnRate(tokensPerMinute: 20_000).tier, .moderate)
        XCTAssertEqual(BurnRate(tokensPerMinute: 59_999).tier, .moderate)
        XCTAssertEqual(BurnRate(tokensPerMinute: 60_000).tier, .high)
    }

    func testFutureTurnsAreNotCounted() {
        XCTAssertNil(BurnRate.calculate(files: [file([turn(minutesAgo: -5, tokens: 90_000)])], now: now))
    }

    // MARK: - pruned

    func testPrunedKeepsOnlyTurnsWithinTheWindowBeforeNow() {
        let kept = turn(minutesAgo: 14, tokens: 1)
        let newest = turn(minutesAgo: 0, tokens: 2)
        let turns = [turn(minutesAgo: 16, tokens: 3), kept, newest, turn(minutesAgo: -60, tokens: 4)]

        XCTAssertEqual(BurnRate.pruned(turns, now: now), [kept, newest])
    }

    // MARK: - Transcript parsing

    func testParsingRecordsDeduplicatedTurnsWithoutCacheReads() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let projectDir = dir.appendingPathComponent("projects/-Users-me-app")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = """
        {"message":{"id":"a","role":"assistant",\
        "usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":2,"cache_read_input_tokens":1000}},\
        "timestamp":"\(timestamp)","requestId":"req_a"}
        """
        try (entry + "\n" + entry + "\n").write(
            to: projectDir.appendingPathComponent("11111111-1111-1111-1111-111111111111.jsonl"),
            atomically: false,
            encoding: .utf8
        )

        var store = TranscriptCacheStore.empty
        _ = TranscriptCache.aggregate(claudeDir: dir, cutoff: nil, store: &store)

        let turns = try XCTUnwrap(store.files.values.first).recentTurns
        XCTAssertEqual(turns.map(\.tokens), [17], "a duplicate streamed chunk is one turn, and cache reads are not fresh work")
    }
}
