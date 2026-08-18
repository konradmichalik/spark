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
        // Reflects the normal shape of real Claude Code usage: cache reads dominate
        // input/output by two orders of magnitude once prompt caching kicks in.
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
        XCTAssertEqual(stats.formattedTokens, "5.1B")
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
}
