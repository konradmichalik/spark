import XCTest
@testable import Spark

final class BurnRateGaugeTests: XCTestCase {
    private let baseline = BurnRateBaseline(median: 1_000, p90: 1_800, rates: Array(stride(from: 100, through: 2_000, by: 100)))

    func testFillIsTheRateOnAScaleOneThirdPastTheNinetiethPercentile() {
        // Scale end: 1,800 * 4/3 = 2,400.
        XCTAssertEqual(BurnRateGaugeLayout(tokensPerMinute: 1_200, baseline: baseline).filled, 10)
        XCTAssertEqual(BurnRateGaugeLayout(tokensPerMinute: 2_400, baseline: baseline).filled, 20)
    }

    func testAnActiveRateAlwaysShowsAtLeastOneDot() {
        XCTAssertEqual(BurnRateGaugeLayout(tokensPerMinute: 1, baseline: baseline).filled, 1)
    }

    func testARateBeyondTheScaleFillsTheGauge() {
        XCTAssertEqual(BurnRateGaugeLayout(tokensPerMinute: 99_999, baseline: baseline).filled, 20)
    }

    func testStrokesSitAtMedianAndP90() {
        let layout = BurnRateGaugeLayout(tokensPerMinute: 1_200, baseline: baseline)

        XCTAssertEqual(layout.medianPosition, 1_000.0 / 2_400.0, accuracy: 0.0001)
        XCTAssertEqual(layout.p90Position, 0.75, accuracy: 0.0001)
    }

    func testThePopoverColumnLightsOneDotPerTier() {
        let steps = [500, 1_000, 1_800].map { BurnRateGaugeLayout(tokensPerMinute: $0, baseline: baseline).tierSteps }

        XCTAssertEqual(steps, [1, 2, 3])
        XCTAssertEqual(steps.max(), BurnRateGaugeLayout.tierStepCount)
    }

    func testLabelsShareARowWhileTheMedianIsFarFromTheP90() {
        XCTAssertFalse(BurnRateGaugeLayout(tokensPerMinute: 1_200, baseline: baseline).stacksLabels)
    }

    func testLabelsStackWhenTheMedianIsCloseToTheP90() {
        let tight = BurnRateBaseline(median: 1_700, p90: 1_800, rates: baseline.rates)
        let equal = BurnRateBaseline(median: 1_800, p90: 1_800, rates: baseline.rates)

        XCTAssertTrue(BurnRateGaugeLayout(tokensPerMinute: 1_200, baseline: tight).stacksLabels)
        XCTAssertTrue(BurnRateGaugeLayout(tokensPerMinute: 1_200, baseline: equal).stacksLabels)
    }

    func testTooltipNamesTheTierAndTheShareOfWindowsBelow() {
        let text = BurnRateFact.tooltip(BurnRate(tokensPerMinute: 1_200), baseline: baseline, explanation: "Explained.")

        XCTAssertEqual(text, "Moderate. Higher than 55% of your active periods in the last 14 days.\nExplained.")
    }

    func testTooltipWithoutAMeasuredBaselineNamesOnlyTheTier() {
        let text = BurnRateFact.tooltip(BurnRate(tokensPerMinute: 70_000), baseline: .fallback, explanation: "Explained.")

        XCTAssertEqual(text, "High\nExplained.")
    }

    func testAccessibilityValueCarriesTheTierAndTheShareOfWindowsBelow() {
        let value = BurnRateFact.accessibilityValue(BurnRate(tokensPerMinute: 1_200), baseline: baseline)

        XCTAssertEqual(value, "1.2K/min tokens, Moderate, higher than 55% of your active periods in the last 14 days")
    }

    func testAccessibilityValueWithoutAMeasuredBaselineNamesOnlyTheTier() {
        let value = BurnRateFact.accessibilityValue(BurnRate(tokensPerMinute: 70_000), baseline: .fallback)

        XCTAssertEqual(value, "70.0K/min tokens, High")
    }
}
