import Foundation

/// Groups a raw Claude model ID into the family the API's usage buckets report on: Sonnet, Opus,
/// or everything else (aggregated into the seven-day all-models figure rather than its own row).
enum ModelFamily: Sendable, Equatable {
    case sonnet
    case opus
    case other

    static func family(forRawModelId rawId: String) -> ModelFamily {
        let lower = rawId.lowercased()
        if lower.contains("sonnet") { return .sonnet }
        if lower.contains("opus") { return .opus }
        return .other
    }

    /// `claude-opus-4-6` -> `Opus 4.6`. Only transforms IDs that actually match Claude's
    /// `claude-<family>-<numeric version segments>` shape; anything else — an unrecognised
    /// model, a future naming scheme, the `<synthetic>` marker — is returned unchanged rather
    /// than mangled or dropped.
    static func displayName(forRawModelId rawId: String) -> String {
        guard rawId.hasPrefix("claude-") else { return rawId }
        let parts = rawId.dropFirst("claude-".count).split(separator: "-").map(String.init)
        guard let familyPart = parts.first, parts.count >= 2,
              parts.dropFirst().allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return rawId
        }
        let family = familyPart.prefix(1).uppercased() + familyPart.dropFirst()
        let version = parts.dropFirst().joined(separator: ".")
        return "\(family) \(version)"
    }
}
