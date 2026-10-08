@testable import Spark
import XCTest

/// One definition of "tokens" across the app: fresh tokens, without cache reads.
final class TokenDefinitionTests: XCTestCase {
    func testVolumeDaysCountFreshTokensOnly() {
        let rollup = DailyRollup(sessionCount: 1, input: 100, output: 50, cacheCreation: 25, cacheRead: 9_000)
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_791_472_800)
        let key = TranscriptCache.dayKey(for: now, calendar: calendar)
        let days = VolumeDaySeries.build(rollups: [key: rollup], timeRange: .sevenDays, now: now, calendar: calendar)
        XCTAssertEqual(days.last?.tokens, 175)
    }

    func testCodexHeadlineLeavesOutCachedInput() {
        var stats = CodexSessionStats()
        stats.inputTokens = 600
        stats.cachedInputTokens = 400
        stats.outputTokens = 200
        XCTAssertEqual(stats.realTokens, 800)
        XCTAssertEqual(stats.totalTokens, 1200)
    }
}

final class TokenWordingTests: XCTestCase {
    func testEveryTokenTooltipExplainsFreshAgainstCacheTokens() {
        XCTAssertEqual(
            TokenWording.claude,
            "Fresh tokens: input, output and cache writes. Cache reads are not counted: that is context Claude re-reads on every turn, "
                + "so it is far larger and says little about what you used."
        )
        XCTAssertEqual(
            TokenWording.codex,
            "Fresh tokens: input and output. Cached input is not counted: that is context Codex re-sends on every turn, "
                + "so it is far larger and says little about what you used."
        )
        XCTAssertEqual(
            TokenWording.volume,
            "Fresh tokens of the days in this range that have ended: input, output and cache writes. "
                + "Cache reads, the context re-read on every turn, are not counted."
        )
    }

    func testBreakdownLeadsWithTheDefinition() {
        XCTAssertEqual(TokenWording.withBreakdown(TokenWording.claude, "Input 1K"), "\(TokenWording.claude)\nInput 1K")
        XCTAssertEqual(TokenWording.withBreakdown("A", "B", average: "C"), "A\nC\nB")
        XCTAssertEqual(TokenWording.withBreakdown("A", "B", average: nil), "A\nB")
    }
}
