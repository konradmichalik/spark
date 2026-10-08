import Foundation

/// One model family's token share for the shown period, ready to render as a row of the report.
struct ModelRow: Identifiable {
    let id: String
    let label: String
    let tokens: Int
    let family: ModelFamily
    /// API-price estimate for the family, `nil` when the cost view is off.
    let cost: Double?
    /// The family's model versions, largest first, with dated snapshots merged into their version.
    let versions: [Version]

    struct Version {
        let label: String
        let tokens: Int
        let cost: Double?
    }

    /// One line per version, e.g. "Opus 5.5 · 40.1M · $120.00", for the legend row's tooltip.
    var versionSummary: String {
        versions
            .map { version in
                var parts = [version.label, formatTokenCount(version.tokens)]
                if let cost = version.cost { parts.append(formatCost(cost)) }
                return parts.joined(separator: " · ")
            }
            .joined(separator: "\n")
    }

    static func rows(from modelTotals: [String: Int], costByModel: [String: Double]? = nil) -> [ModelRow] {
        let families: [(ModelFamily, String)] = [(.sonnet, "Sonnet"), (.opus, "Opus"), (.fable, "Fable"), (.other, "Other")]
        let rows: [ModelRow] = families.compactMap { family, label in
            let versions = versions(of: family, modelTotals: modelTotals, costByModel: costByModel)
            let tokens = versions.reduce(0) { $0 + $1.tokens }
            guard tokens > 0 else { return nil }
            let cost = costByModel.map { _ in versions.reduce(0) { $0 + ($1.cost ?? 0) } }
            return ModelRow(id: label, label: label, tokens: tokens, family: family, cost: cost, versions: versions)
        }
        return rows.enumerated()
            .sorted { $0.element.tokens != $1.element.tokens ? $0.element.tokens > $1.element.tokens : $0.offset < $1.offset }
            .map(\.element)
    }

    /// Covers every model with tokens or a cost: a model with only cache reads has no real tokens
    /// but still costs money, and the family's cost is summed from these.
    private static func versions(
        of family: ModelFamily,
        modelTotals: [String: Int],
        costByModel: [String: Double]?
    ) -> [Version] {
        let rawIds = Set(modelTotals.keys).union(costByModel.map { Set($0.keys) } ?? [])
        var tokensByLabel: [String: Int] = [:]
        var costByLabel: [String: Double] = [:]
        for rawId in rawIds where ModelFamily.family(forRawModelId: rawId) == family {
            let label = ModelFamily.displayName(forRawModelId: rawId)
            tokensByLabel[label, default: 0] += modelTotals[rawId] ?? 0
            if let cost = costByModel?[rawId] { costByLabel[label, default: 0] += cost }
        }
        return tokensByLabel
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { Version(label: $0.key, tokens: $0.value, cost: costByLabel[$0.key]) }
    }
}
