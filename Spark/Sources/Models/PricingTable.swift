import Foundation

/// USD per token for one model.
struct ModelPrice: Codable, Equatable, Sendable {
    let input: Double
    let output: Double
    let cacheCreation: Double
    let cacheRead: Double

    func cost(of totals: ModelTokenTotals) -> Double {
        Double(totals.input) * input
            + Double(totals.output) * output
            + Double(totals.cacheCreation) * cacheCreation
            + Double(totals.cacheRead) * cacheRead
    }
}

struct CostEstimate: Equatable, Sendable {
    let total: Double
    /// Raw model IDs that consumed tokens but have no price — their cost is missing from `total`.
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
