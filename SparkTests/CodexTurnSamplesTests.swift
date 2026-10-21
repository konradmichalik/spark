import XCTest
@testable import Spark

final class CodexTurnSamplesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_598_400)

    private func tokenCount(_ time: Date, input: Int, cached: Int, output: Int) -> String {
        let timestamp = ISO8601DateFormatter().string(from: time)
        let usage = #"{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"output_tokens":\#(output)}"#
        return #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":\#(usage)}}}"#
    }

    func testUsesPreCutoffCumulativeEventAsBaselineAndExcludesCachedInput() {
        let cutoff = now.addingTimeInterval(-BurnRate.window)
        let content = [
            tokenCount(cutoff.addingTimeInterval(-1), input: 1_000, cached: 400, output: 100),
            tokenCount(now.addingTimeInterval(-60), input: 2_000, cached: 900, output: 300),
            tokenCount(now.addingTimeInterval(-59), input: 2_000, cached: 900, output: 300)
        ].joined(separator: "\n")

        let samples = CodexTurnSamples.parseFile(content: content, cutoff: cutoff, now: now)

        XCTAssertEqual(samples, [TurnSample(date: now.addingTimeInterval(-60), tokens: 700)])
    }

    func testDropsEventsOutsideWindowAndInTheFuture() {
        let cutoff = now.addingTimeInterval(-BurnRate.window)
        let content = [
            tokenCount(cutoff.addingTimeInterval(-1), input: 100, cached: 0, output: 0),
            tokenCount(now.addingTimeInterval(1), input: 200, cached: 0, output: 0)
        ].joined(separator: "\n")

        XCTAssertTrue(CodexTurnSamples.parseFile(content: content, cutoff: cutoff, now: now).isEmpty)
    }

    func testCounterResetStartsFromZero() {
        let cutoff = now.addingTimeInterval(-BurnRate.window)
        let content = [
            tokenCount(now.addingTimeInterval(-120), input: 5_000, cached: 2_000, output: 800),
            tokenCount(now.addingTimeInterval(-60), input: 300, cached: 20, output: 50)
        ].joined(separator: "\n")

        let samples = CodexTurnSamples.parseFile(content: content, cutoff: cutoff, now: now)

        XCTAssertEqual(samples.last?.tokens, 330)
    }
}
