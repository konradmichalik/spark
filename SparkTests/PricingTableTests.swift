import XCTest
@testable import Spark

final class PricingTableTests: XCTestCase {

    private let sample = Data("""
    {
      "sample_spec": {"input_cost_per_token": 0},
      "gpt-4o": {"input_cost_per_token": 0.0000025, "output_cost_per_token": 0.00001},
      "claude-opus-4-5-20251101": {
        "input_cost_per_token": 0.000005,
        "output_cost_per_token": 0.000025,
        "cache_creation_input_token_cost": 0.00000625,
        "cache_creation_input_token_cost_above_1hr": 0.00001,
        "cache_read_input_token_cost": 5e-7
      },
      "claude-sonnet-5-5": {
        "input_cost_per_token": 0.000003,
        "output_cost_per_token": 0.000015
      },
      "claude-broken": {"input_cost_per_token": 0.000003}
    }
    """.utf8)

    // MARK: - parse

    func testParseKeepsOnlyClaudeEntriesWithInputAndOutputPrice() throws {
        let table = try PricingTable.parse(sample)

        XCTAssertEqual(Set(table.prices.keys), ["claude-opus-4-5-20251101", "claude-sonnet-5-5"])
    }

    func testParseReadsAllTokenPrices() throws {
        let price = try XCTUnwrap(PricingTable.parse(sample).prices["claude-opus-4-5-20251101"])

        XCTAssertEqual(price.input, 0.000005, accuracy: 1e-12)
        XCTAssertEqual(price.output, 0.000025, accuracy: 1e-12)
        XCTAssertEqual(price.cacheCreation, 0.00000625, accuracy: 1e-12)
        XCTAssertEqual(price.cacheCreation1h, 0.00001, accuracy: 1e-12)
        XCTAssertEqual(price.cacheRead, 5e-7, accuracy: 1e-12)
    }

    func testParseDerivesMissingCachePricesFromInputPrice() throws {
        let price = try XCTUnwrap(PricingTable.parse(sample).prices["claude-sonnet-5-5"])

        XCTAssertEqual(price.cacheCreation, 0.000003 * 1.25, accuracy: 1e-12)
        XCTAssertEqual(price.cacheCreation1h, 0.000003 * 2, accuracy: 1e-12)
        XCTAssertEqual(price.cacheRead, 0.000003 * 0.1, accuracy: 1e-12)
    }

    func testDecodingAPriceCachedBeforeTheOneHourRateDerivesIt() throws {
        let cached = Data(#"{"input":0.000003,"output":0.000015,"cacheCreation":0.00000375,"cacheRead":3e-7}"#.utf8)

        let price = try JSONDecoder().decode(ModelPrice.self, from: cached)

        XCTAssertEqual(price.cacheCreation1h, 0.000003 * 2, accuracy: 1e-12)
    }

    func testParseThrowsOnInvalidJSON() {
        XCTAssertThrowsError(try PricingTable.parse(Data("nope".utf8)))
    }

    // MARK: - price(forRawModelId:)

    func testPriceMatchesExactId() throws {
        let table = try PricingTable.parse(sample)

        XCTAssertNotNil(table.price(forRawModelId: "claude-sonnet-5-5"))
    }

    func testPriceMatchesDatedIdAgainstUndatedEntry() throws {
        let table = try PricingTable.parse(sample)

        XCTAssertEqual(
            table.price(forRawModelId: "claude-sonnet-5-5-20260101"),
            table.prices["claude-sonnet-5-5"]
        )
    }

    func testPriceMatchesUndatedIdAgainstDatedEntry() throws {
        let table = try PricingTable.parse(sample)

        XCTAssertEqual(
            table.price(forRawModelId: "claude-opus-4-5"),
            table.prices["claude-opus-4-5-20251101"]
        )
    }

    func testPriceDoesNotMatchADifferentVersion() throws {
        let table = try PricingTable.parse(sample)

        XCTAssertNil(table.price(forRawModelId: "claude-opus-4-6"))
        XCTAssertNil(table.price(forRawModelId: "<synthetic>"))
    }

    // MARK: - cost

    func testCostSumsAllFourTokenKinds() throws {
        let table = try PricingTable.parse(sample)
        let totals = ModelTokenTotals(input: 1_000_000, output: 100_000, cacheCreation: 200_000, cacheRead: 4_000_000)

        let cost = table.cost(forModelTotals: ["claude-opus-4-5-20251101": totals])

        // 5 + 2.5 + 1.25 + 2.0
        XCTAssertEqual(cost.total, 10.75, accuracy: 1e-9)
        XCTAssertTrue(cost.unpricedModels.isEmpty)
    }

    func testCostPricesOneHourCacheWritesAtTheOneHourRate() throws {
        let table = try PricingTable.parse(sample)
        let totals = ModelTokenTotals(input: 0, output: 0, cacheCreation: 1_000_000, cacheRead: 0, cacheCreation1h: 800_000)

        let cost = table.cost(forModelTotals: ["claude-opus-4-5-20251101": totals])

        // 200k at 5m (1.25) + 800k at 1h (8.0)
        XCTAssertEqual(cost.total, 9.25, accuracy: 1e-9)
    }

    func testCostReportsModelsWithoutPriceInsteadOfCountingThem() throws {
        let table = try PricingTable.parse(sample)
        let totals = ModelTokenTotals(input: 1_000_000, output: 0, cacheCreation: 0, cacheRead: 0)

        let cost = table.cost(forModelTotals: [
            "claude-sonnet-5-5": totals,
            "claude-future-9": totals
        ])

        XCTAssertEqual(cost.total, 3.0, accuracy: 1e-9)
        XCTAssertEqual(cost.unpricedModels, ["claude-future-9"])
    }

    // MARK: - summary

    func testSummaryBreaksCostDownByModelAndProject() throws {
        let table = try PricingTable.parse(sample)
        let million = ModelTokenTotals(input: 1_000_000, output: 0, cacheCreation: 0, cacheRead: 0)
        let modelTotals = [
            "claude-opus-4-5-20251101": ModelTokenTotals(input: 2_000_000, output: 0, cacheCreation: 0, cacheRead: 0),
            "claude-sonnet-5-5": million
        ]
        let projectModelTotals = [
            "-Users-a": ["claude-opus-4-5-20251101": million, "claude-sonnet-5-5": million],
            "-Users-b": ["claude-opus-4-5-20251101": million]
        ]

        let summary = table.summary(modelTotals: modelTotals, projectModelTotals: projectModelTotals)

        XCTAssertEqual(summary.total, 13.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(summary.byModel["claude-opus-4-5-20251101"]), 10.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(summary.byModel["claude-sonnet-5-5"]), 3.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(summary.byProject["-Users-a"]), 8.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(summary.byProject["-Users-b"]), 5.0, accuracy: 1e-9)
    }

    func testSummaryLeavesUnpricedModelsOutOfEveryBreakdown() throws {
        let table = try PricingTable.parse(sample)
        let million = ModelTokenTotals(input: 1_000_000, output: 0, cacheCreation: 0, cacheRead: 0)

        let summary = table.summary(
            modelTotals: ["claude-future-9": million],
            projectModelTotals: ["-Users-a": ["claude-future-9": million]]
        )

        XCTAssertEqual(summary.total, 0)
        XCTAssertEqual(summary.unpricedModels, ["claude-future-9"])
        XCTAssertTrue(summary.byModel.isEmpty)
        XCTAssertEqual(summary.byProject["-Users-a"], 0)
    }

    func testCostIgnoresModelsWithoutTokens() throws {
        let table = try PricingTable.parse(sample)

        let cost = table.cost(forModelTotals: ["<synthetic>": ModelTokenTotals()])

        XCTAssertEqual(cost.total, 0)
        XCTAssertTrue(cost.unpricedModels.isEmpty)
    }
}
