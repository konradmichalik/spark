import XCTest
@testable import Spark

final class BurnRateBaselineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var currentWindow: Int { BurnRateBaseline.windowIndex(of: now) }

    /// One completed window per entry, `n` windows back from the current one, `tokens` fresh tokens each.
    private func windows(_ tokensByAge: [Int: Int]) -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: tokensByAge.map { (currentWindow - $0.key, $0.value) })
    }

    private func evenWindows(count: Int, tokensPerStep: Int = 1_500) -> [Int: Int] {
        windows(Dictionary(uniqueKeysWithValues: (1...count).map { ($0, $0 * tokensPerStep) }))
    }

    func testMedianAndP90AreNearestRankPercentilesOfTheWindowRates() {
        let baseline = BurnRateBaseline.calculate(windowTokens: evenWindows(count: 20), now: now)

        // 20 windows at 100, 200 ... 2000 tokens/min.
        XCTAssertEqual(baseline.median, 1_000)
        XCTAssertEqual(baseline.p90, 1_800)
    }

    func testTooFewWindowsFallBackToTheFixedThresholds() {
        let baseline = BurnRateBaseline.calculate(windowTokens: evenWindows(count: 19), now: now)

        XCTAssertEqual(baseline, .fallback)
        XCTAssertEqual(BurnRateBaseline.fallback.median, 20_000)
        XCTAssertEqual(BurnRateBaseline.fallback.p90, 60_000)
    }

    func testTheWindowStillFillingIsLeftOut() {
        var tokens = evenWindows(count: 20)
        tokens[currentWindow] = 15_000_000

        let baseline = BurnRateBaseline.calculate(windowTokens: tokens, now: now)

        XCTAssertEqual(baseline.p90, 1_800)
    }

    func testWindowsOlderThanFourteenDaysAreLeftOut() {
        let perDay = 24 * 4
        var tokens = evenWindows(count: 20)
        tokens[currentWindow - 14 * perDay - 1] = 15_000_000

        let baseline = BurnRateBaseline.calculate(windowTokens: tokens, now: now)

        XCTAssertEqual(baseline.p90, 1_800)
    }

    func testIdleWindowsDoNotCount() {
        var tokens = evenWindows(count: 20)
        tokens[currentWindow - 50] = 0

        let baseline = BurnRateBaseline.calculate(windowTokens: tokens, now: now)

        XCTAssertEqual(baseline.median, 1_000)
    }

    func testPercentIsTheShareOfWindowsBelowTheRate() {
        let baseline = BurnRateBaseline.calculate(windowTokens: evenWindows(count: 20), now: now)

        XCTAssertEqual(baseline.percent(of: 1_050), 50)
        XCTAssertEqual(baseline.percent(of: 50), 0)
        XCTAssertEqual(baseline.percent(of: 5_000), 100)
    }

    func testThereIsNoPercentForTheFallback() {
        XCTAssertNil(BurnRateBaseline.fallback.percent(of: 30_000))
    }

    func testTierFollowsTheBaseline() {
        let baseline = BurnRateBaseline.calculate(windowTokens: evenWindows(count: 20), now: now)

        XCTAssertEqual(BurnRate(tokensPerMinute: 999).tier(in: baseline), .normal)
        XCTAssertEqual(BurnRate(tokensPerMinute: 1_000).tier(in: baseline), .moderate)
        XCTAssertEqual(BurnRate(tokensPerMinute: 1_799).tier(in: baseline), .moderate)
        XCTAssertEqual(BurnRate(tokensPerMinute: 1_800).tier(in: baseline), .high)
    }

    func testWindowTokensSumsTurnsPerWindow() {
        let start = Date(timeIntervalSince1970: 900 * 1_000)
        let turns = [
            TurnSample(date: start, tokens: 100),
            TurnSample(date: start.addingTimeInterval(899), tokens: 50),
            TurnSample(date: start.addingTimeInterval(900), tokens: 7)
        ]

        XCTAssertEqual(BurnRateBaseline.windowTokens(of: turns), [1_000: 150, 1_001: 7])
    }

    func testWindowIndexAlignsToFifteenMinutes() {
        let start = Date(timeIntervalSince1970: 900 * 1_000)

        XCTAssertEqual(BurnRateBaseline.windowIndex(of: start), 1_000)
        XCTAssertEqual(BurnRateBaseline.windowIndex(of: start.addingTimeInterval(899)), 1_000)
        XCTAssertEqual(BurnRateBaseline.windowIndex(of: start.addingTimeInterval(900)), 1_001)
    }
}
