import XCTest
@testable import Spark

final class StatsModelsTests: XCTestCase {

    // MARK: - StatsPeriod.startDate

    func testTodayStartsAtMidnight() {
        guard let startDate = StatsPeriod.today.startDate else {
            return XCTFail("today period should have a start date")
        }
        XCTAssertTrue(Calendar.current.isDateInToday(startDate))
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: startDate)
        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(components.second, 0)
    }

    func testWeekStartsSevenDaysAgo() {
        guard let startDate = StatsPeriod.week.startDate else {
            return XCTFail("week period should have a start date")
        }
        let expected = Date().addingTimeInterval(-7 * 24 * 3600)
        XCTAssertEqual(startDate.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 5)
    }

    func testMonthStartsThirtyDaysAgo() {
        guard let startDate = StatsPeriod.month.startDate else {
            return XCTFail("month period should have a start date")
        }
        let expected = Date().addingTimeInterval(-30 * 24 * 3600)
        XCTAssertEqual(startDate.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 5)
    }

    func testAllHasNoStartDate() {
        XCTAssertNil(StatsPeriod.all.startDate)
    }

    // MARK: - LiveStats

    func testTotalTokensSumsAllFourFields() {
        let stats = LiveStats(
            period: .today,
            messageCount: 5,
            sessionCount: 1,
            inputTokens: 100,
            outputTokens: 50,
            cacheCreationTokens: 20,
            cacheReadTokens: 30
        )
        XCTAssertEqual(stats.totalTokens, 200)
    }

    func testFormattedTokensUsesCompactNotation() {
        let stats = LiveStats(
            period: .all,
            messageCount: 1,
            sessionCount: 1,
            inputTokens: 1_200_000,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0
        )
        XCTAssertEqual(stats.formattedTokens, "1.2M")
    }

    func testFormattedTokensUsesBillionsNotation() {
        let stats = LiveStats(
            period: .today,
            messageCount: 1,
            sessionCount: 1,
            inputTokens: 200_000_000,
            outputTokens: 900_000_000,
            cacheCreationTokens: 200_000_000,
            cacheReadTokens: 0
        )
        XCTAssertEqual(stats.formattedTokens, "1.3B")
    }

    func testFormattedTokensExcludesCacheReads() {
        // Reflects the normal shape of real Claude Code usage: cache reads dominate
        // input/output by two orders of magnitude once prompt caching kicks in, but they're
        // reused context, not fresh consumption, so the headline number leaves them out.
        let stats = LiveStats(
            period: .today,
            messageCount: 1,
            sessionCount: 1,
            inputTokens: 53_166,
            outputTokens: 13_663_194,
            cacheCreationTokens: 57_110_168,
            cacheReadTokens: 4_997_419_883
        )
        XCTAssertEqual(stats.totalTokens, 5_068_246_411)
        XCTAssertEqual(stats.realTokens, 70_826_528)
        XCTAssertEqual(stats.formattedTokens, "70.8M")
    }

    // MARK: - Per-model token attribution

    func testTokensForFamilySumsMatchingModelsOnly() {
        let stats = LiveStats(
            period: .today,
            messageCount: 1,
            sessionCount: 1,
            inputTokens: 0,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            modelTotals: [
                "claude-opus-4-6": 100,
                "claude-opus-5": 50,
                "claude-sonnet-5": 30,
                "claude-haiku-4-5": 10
            ]
        )

        XCTAssertEqual(stats.tokens(for: .opus), 150)
        XCTAssertEqual(stats.tokens(for: .sonnet), 30)
        XCTAssertEqual(stats.tokens(for: .other), 10)
    }

    func testTokensForFamilyIsZeroWhenNoModelsMatch() {
        let stats = LiveStats(
            period: .today,
            messageCount: 1,
            sessionCount: 1,
            inputTokens: 0,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            modelTotals: ["claude-haiku-4-5": 10]
        )

        XCTAssertEqual(stats.tokens(for: .opus), 0)
    }

    // MARK: - Assistant entry deduplication

    func testDeduplicatorCountsFirstOccurrence() {
        var dedup = TranscriptCache.TokenDeduplicator()
        XCTAssertTrue(dedup.shouldCount(messageId: "msg_1", requestId: "req_1"))
    }

    func testDeduplicatorSkipsRepeatedMessageAndRequestId() {
        var dedup = TranscriptCache.TokenDeduplicator()
        XCTAssertTrue(dedup.shouldCount(messageId: "msg_1", requestId: "req_1"))
        XCTAssertFalse(dedup.shouldCount(messageId: "msg_1", requestId: "req_1"))
        XCTAssertFalse(dedup.shouldCount(messageId: "msg_1", requestId: "req_1"))
    }

    func testDeduplicatorCountsSameMessageIdWithDifferentRequestIdSeparately() {
        var dedup = TranscriptCache.TokenDeduplicator()
        XCTAssertTrue(dedup.shouldCount(messageId: "msg_1", requestId: "req_1"))
        XCTAssertTrue(dedup.shouldCount(messageId: "msg_1", requestId: "req_2"))
    }

    func testDeduplicatorDoesNotCollideAcrossFieldBoundaries() {
        // "a:b" + "c" and "a" + "b:c" would both concatenate to the same "a:b:c" string key,
        // so a naive string-based key would misreport the second pair as a duplicate.
        var dedup = TranscriptCache.TokenDeduplicator()
        XCTAssertTrue(dedup.shouldCount(messageId: "a:b", requestId: "c"))
        XCTAssertTrue(dedup.shouldCount(messageId: "a", requestId: "b:c"))
    }

    func testDeduplicatorAlwaysCountsEntriesMissingEitherField() {
        var dedup = TranscriptCache.TokenDeduplicator()
        XCTAssertTrue(dedup.shouldCount(messageId: nil, requestId: "req_1"))
        XCTAssertTrue(dedup.shouldCount(messageId: nil, requestId: "req_1"))
        XCTAssertTrue(dedup.shouldCount(messageId: "msg_1", requestId: nil))
        XCTAssertTrue(dedup.shouldCount(messageId: "msg_1", requestId: nil))
        XCTAssertTrue(dedup.shouldCount(messageId: nil, requestId: nil))
    }

    func testDeduplicatorReproducesMeasuredThreeToOneOvercount() {
        // 7 distinct responses, each streamed as 3 usage-bearing entries (text + 2 tool_use
        // blocks) sharing the same message.id/requestId — the pattern found in real transcripts.
        var dedup = TranscriptCache.TokenDeduplicator()
        var countedEntries = 0
        for messageIndex in 0..<7 {
            for _ in 0..<3 where dedup.shouldCount(messageId: "msg_\(messageIndex)", requestId: "req_\(messageIndex)") {
                countedEntries += 1
            }
        }
        XCTAssertEqual(countedEntries, 7)
    }

    // MARK: - Top projects

    func testTopProjectsRanksByTokenVolumeDescending() {
        let stats = LiveStats(
            period: .today,
            messageCount: 1,
            sessionCount: 1,
            inputTokens: 0,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            projectTotals: ["-Users-a": 10, "-Users-b": 100, "-Users-c": 50],
            projectDisplayNames: [:]
        )

        let top = stats.topProjects(limit: 3)

        XCTAssertEqual(top.map(\.key), ["-Users-b", "-Users-c", "-Users-a"])
        XCTAssertEqual(top.map(\.tokens), [100, 50, 10])
    }

    func testTopProjectsRespectsLimit() {
        let stats = LiveStats(
            period: .today,
            messageCount: 1,
            sessionCount: 1,
            inputTokens: 0,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            projectTotals: ["-Users-a": 10, "-Users-b": 100, "-Users-c": 50, "-Users-d": 5],
            projectDisplayNames: [:]
        )

        XCTAssertEqual(stats.topProjects(limit: 2).map(\.key), ["-Users-b", "-Users-c"])
    }

    func testTopProjectsUsesResolvedDisplayNameWhenAvailable() {
        let stats = LiveStats(
            period: .today,
            messageCount: 1,
            sessionCount: 1,
            inputTokens: 0,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            projectTotals: ["-Users-konrad-dev-typo3-routing": 10],
            projectDisplayNames: ["-Users-konrad-dev-typo3-routing": "/Users/konrad/dev/typo3-routing"]
        )

        XCTAssertEqual(stats.topProjects(limit: 1).first?.displayName, "typo3-routing")
    }
}
