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

    func testTotalTokensSumsInputAndOutput() {
        let stats = LiveStats(period: .today, messageCount: 5, sessionCount: 1, inputTokens: 100, outputTokens: 50)
        XCTAssertEqual(stats.totalTokens, 150)
    }

    func testFormattedTokensUsesCompactNotation() {
        let stats = LiveStats(period: .all, messageCount: 1, sessionCount: 1, inputTokens: 1_200_000, outputTokens: 0)
        XCTAssertEqual(stats.formattedTokens, "1.2M")
    }

    // MARK: - Assistant entry deduplication

    func testDeduplicatorCountsFirstOccurrence() {
        var dedup = LiveStatsParser.TokenDeduplicator()
        XCTAssertTrue(dedup.shouldCount(messageId: "msg_1", requestId: "req_1"))
    }

    func testDeduplicatorSkipsRepeatedMessageAndRequestId() {
        var dedup = LiveStatsParser.TokenDeduplicator()
        XCTAssertTrue(dedup.shouldCount(messageId: "msg_1", requestId: "req_1"))
        XCTAssertFalse(dedup.shouldCount(messageId: "msg_1", requestId: "req_1"))
        XCTAssertFalse(dedup.shouldCount(messageId: "msg_1", requestId: "req_1"))
    }

    func testDeduplicatorCountsSameMessageIdWithDifferentRequestIdSeparately() {
        var dedup = LiveStatsParser.TokenDeduplicator()
        XCTAssertTrue(dedup.shouldCount(messageId: "msg_1", requestId: "req_1"))
        XCTAssertTrue(dedup.shouldCount(messageId: "msg_1", requestId: "req_2"))
    }

    func testDeduplicatorDoesNotCollideAcrossFieldBoundaries() {
        // "a:b" + "c" and "a" + "b:c" would both concatenate to the same "a:b:c" string key,
        // so a naive string-based key would misreport the second pair as a duplicate.
        var dedup = LiveStatsParser.TokenDeduplicator()
        XCTAssertTrue(dedup.shouldCount(messageId: "a:b", requestId: "c"))
        XCTAssertTrue(dedup.shouldCount(messageId: "a", requestId: "b:c"))
    }

    func testDeduplicatorAlwaysCountsEntriesMissingEitherField() {
        var dedup = LiveStatsParser.TokenDeduplicator()
        XCTAssertTrue(dedup.shouldCount(messageId: nil, requestId: "req_1"))
        XCTAssertTrue(dedup.shouldCount(messageId: nil, requestId: "req_1"))
        XCTAssertTrue(dedup.shouldCount(messageId: "msg_1", requestId: nil))
        XCTAssertTrue(dedup.shouldCount(messageId: "msg_1", requestId: nil))
        XCTAssertTrue(dedup.shouldCount(messageId: nil, requestId: nil))
    }

    func testDeduplicatorReproducesMeasuredThreeToOneOvercount() {
        // 7 distinct responses, each streamed as 3 usage-bearing entries (text + 2 tool_use
        // blocks) sharing the same message.id/requestId — the pattern found in real transcripts.
        var dedup = LiveStatsParser.TokenDeduplicator()
        var countedEntries = 0
        for messageIndex in 0..<7 {
            for _ in 0..<3 where dedup.shouldCount(messageId: "msg_\(messageIndex)", requestId: "req_\(messageIndex)") {
                countedEntries += 1
            }
        }
        XCTAssertEqual(countedEntries, 7)
    }
}
