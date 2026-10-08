@testable import Spark
import XCTest

final class StatisticsTextTests: XCTestCase {
    func testCountsStayGroupedUntilTheyNeedToShrink() {
        XCTAssertEqual(UsageFormat.count(130), NumberParts(number: "130", unit: ""))
        XCTAssertEqual(UsageFormat.count(7015), NumberParts(number: "7,015", unit: ""))
        XCTAssertEqual(UsageFormat.count(12_345), NumberParts(number: "12.3", unit: "K"))
        XCTAssertEqual(UsageFormat.count(-4), NumberParts(number: "0", unit: ""))
    }

    func testCostTooltipExplainsTheEstimate() {
        let cost = CostSummary(total: 117, byModel: [:], byProject: [:], bySession: [:], unpricedModels: [])
        XCTAssertEqual(StatisticsText.costTooltip(cost), "Estimated: tokens priced at API list prices. Not what your subscription costs.")
        let partial = CostSummary(total: 117, byModel: [:], byProject: [:], bySession: [:], unpricedModels: ["claude-x", "claude-y"])
        XCTAssertEqual(
            StatisticsText.costTooltip(partial),
            "Estimated: tokens priced at API list prices. Not what your subscription costs. No price for claude-x, claude-y."
        )
    }

    func testShareIsRelativeToTheLargestEntry() {
        XCTAssertEqual(StatisticsText.share(250, of: 1000), 25)
        XCTAssertEqual(StatisticsText.share(5, of: 0), 0)
    }

    func testProjectTooltipCarriesItsCost() {
        XCTAssertEqual(StatisticsText.projectTooltip(tokens: 1_200_000, cost: 12.4), "1.2M tokens\n\u{2248} $12.40 at API list prices")
        XCTAssertEqual(StatisticsText.projectTooltip(tokens: 1_200_000, cost: nil), "1.2M tokens")
    }

    func testCodexModelsRankByTokens() {
        var stats = CodexSessionStats()
        stats.modelTokens = ["gpt-5": 100, "gpt-5-codex": 900, "o3": 0]
        XCTAssertEqual(StatisticsText.rankedModels(stats).map(\.name), ["gpt-5-codex", "gpt-5"])
        XCTAssertEqual(StatisticsText.rankedModels(stats).map(\.tokens), [900, 100])
    }
}
