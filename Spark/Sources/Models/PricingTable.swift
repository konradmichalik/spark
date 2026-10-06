import Foundation

/// USD per token for one model.
struct ModelPrice: Codable, Equatable, Sendable {
    let input: Double
    let output: Double
    /// The 5-minute cache write rate.
    let cacheCreation: Double
    let cacheCreation1h: Double
    let cacheRead: Double

    func cost(of totals: ModelTokenTotals) -> Double {
        Double(totals.input) * input
            + Double(totals.output) * output
            + Double(totals.cacheCreation - totals.cacheCreation1h) * cacheCreation
            + Double(totals.cacheCreation1h) * cacheCreation1h
            + Double(totals.cacheRead) * cacheRead
    }
}

extension ModelPrice {
    static let cacheCreation1hMultiplier = 2.0

    private enum CodingKeys: String, CodingKey {
        case input, output, cacheCreation, cacheCreation1h, cacheRead
    }

    /// A `pricing.json` cached before the 1h rate existed has no `cacheCreation1h`. Deriving it
    /// keeps that cache usable as the offline fallback instead of failing to decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let input = try container.decode(Double.self, forKey: .input)
        self.init(
            input: input,
            output: try container.decode(Double.self, forKey: .output),
            cacheCreation: try container.decode(Double.self, forKey: .cacheCreation),
            cacheCreation1h: try container.decodeIfPresent(Double.self, forKey: .cacheCreation1h)
                ?? input * Self.cacheCreation1hMultiplier,
            cacheRead: try container.decode(Double.self, forKey: .cacheRead)
        )
    }
}

struct CostEstimate: Equatable, Sendable {
    let total: Double
    /// Raw model IDs that consumed tokens but have no price — their cost is missing from `total`.
    let unpricedModels: [String]
}

/// The estimate shown in the usage report. Models without a price are in `unpricedModels` and
/// missing from `total`, `byModel` and `byProject`.
struct CostSummary: Equatable, Sendable {
    let total: Double
    let byModel: [String: Double]
    /// Keyed by the encoded project directory name, like `LiveStats.projectTotals`.
    let byProject: [String: Double]
    let unpricedModels: [String]
}

/// Claude prices from the LiteLLM `model_prices_and_context_window.json`, keyed by raw model ID.
struct PricingTable: Codable, Equatable, Sendable {
    let prices: [String: ModelPrice]

    /// Cache write and cache read are billed as multiples of the input price, used when the
    /// source omits them.
    private static let cacheCreationMultiplier = 1.25
    private static let cacheReadMultiplier = 0.1

    static func parse(_ data: Data) throws -> PricingTable {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        var prices: [String: ModelPrice] = [:]
        for (key, value) in root where isClaudeModelKey(key) {
            guard let entry = value as? [String: Any],
                  let input = entry["input_cost_per_token"] as? Double,
                  let output = entry["output_cost_per_token"] as? Double else { continue }
            prices[key] = ModelPrice(
                input: input,
                output: output,
                cacheCreation: entry["cache_creation_input_token_cost"] as? Double
                    ?? input * cacheCreationMultiplier,
                cacheCreation1h: entry["cache_creation_input_token_cost_above_1hr"] as? Double
                    ?? input * ModelPrice.cacheCreation1hMultiplier,
                cacheRead: entry["cache_read_input_token_cost"] as? Double
                    ?? input * cacheReadMultiplier
            )
        }
        return PricingTable(prices: prices)
    }

    /// Exact ID first, then the same model with the date suffix ignored on either side
    /// (`claude-opus-4-5` against `claude-opus-4-5-20251101`). A different version never matches.
    func price(forRawModelId rawId: String) -> ModelPrice? {
        if let exact = prices[rawId] { return exact }
        let base = Self.withoutDateSuffix(rawId)
        return prices
            .filter { Self.withoutDateSuffix($0.key) == base }
            .min { $0.key < $1.key }?
            .value
    }

    func cost(forModelTotals modelTotals: [String: ModelTokenTotals]) -> CostEstimate {
        var total = 0.0
        var unpriced: [String] = []
        for (model, totals) in modelTotals where totals.total > 0 {
            if let price = price(forRawModelId: model) {
                total += price.cost(of: totals)
            } else {
                unpriced.append(model)
            }
        }
        return CostEstimate(total: total, unpricedModels: unpriced.sorted())
    }

    func summary(
        modelTotals: [String: ModelTokenTotals],
        projectModelTotals: [String: [String: ModelTokenTotals]]
    ) -> CostSummary {
        let estimate = cost(forModelTotals: modelTotals)
        let byModel = modelTotals.reduce(into: [String: Double]()) { result, entry in
            if let price = price(forRawModelId: entry.key), entry.value.total > 0 {
                result[entry.key] = price.cost(of: entry.value)
            }
        }
        let byProject = projectModelTotals.mapValues { cost(forModelTotals: $0).total }
        return CostSummary(
            total: estimate.total,
            byModel: byModel,
            byProject: byProject,
            unpricedModels: estimate.unpricedModels
        )
    }

    /// Provider-prefixed (`bedrock/...`) and versioned (`...-v1:0`) entries are other offerings
    /// of the same models.
    private static func isClaudeModelKey(_ key: String) -> Bool {
        key.hasPrefix("claude-") && !key.contains("/") && !key.contains(":")
    }

    private static func withoutDateSuffix(_ id: String) -> String {
        guard let range = id.range(of: #"-\d{8}$"#, options: .regularExpression) else { return id }
        return String(id[..<range.lowerBound])
    }
}
