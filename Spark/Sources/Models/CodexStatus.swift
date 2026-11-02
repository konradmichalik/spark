import Foundation

// MARK: - Codex Status

struct CodexStatusComponent: Equatable {
    let name: String
    let status: ClaudeServiceStatus
}

/// What Spark knows about the Codex parts of the OpenAI status page. The page also lists the
/// API and ChatGPT, which an incident may hit without touching Codex, so only the components
/// named Codex count.
struct CodexStatusSnapshot: Equatable {
    let components: [CodexStatusComponent]

    static let unavailable = CodexStatusSnapshot(components: [])

    var overall: ClaudeServiceStatus {
        guard !components.isEmpty else { return .unknown }
        return components.map(\.status).max { $0.severity < $1.severity } ?? .unknown
    }

    var description: String {
        components.isEmpty ? "Status unavailable" : "Codex: \(overall.displayName)"
    }
}

private extension ClaudeServiceStatus {
    var severity: Int {
        switch self {
        case .majorOutage: 3
        case .partialOutage: 2
        case .degradedPerformance: 1
        case .operational, .none, .unknown: 0
        }
    }
}

// MARK: - Response

/// The page's own endpoint (`/proxy/status.openai.com`). Undocumented and unlike Statuspage's
/// `summary.json`, which has no incidents and a stale timestamp. Every field except the
/// component list is optional, so a changed shape degrades to "operational" for the components
/// instead of failing the whole decode.
struct CodexStatusResponse: Decodable {
    private let summary: Summary

    private struct Summary: Decodable {
        let components: [Component]
        let affectedComponents: [Affected]

        enum CodingKeys: String, CodingKey {
            case components
            case affectedComponents = "affected_components"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            components = try container.decode([Component].self, forKey: .components)
            affectedComponents = (try? container.decodeIfPresent([Affected].self, forKey: .affectedComponents)) ?? []
        }
    }

    private struct Component: Decodable {
        let id: String
        let name: String
    }

    /// The component id and impact of one affected component. Both keys are guesses from
    /// incident.io's API, so an entry that lacks them still counts as degraded.
    private struct Affected: Decodable {
        let id: String?
        let status: String?

        enum CodingKeys: String, CodingKey {
            case componentId = "component_id"
            case id
            case status
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? container.decodeIfPresent(String.self, forKey: .componentId))
                ?? (try? container.decodeIfPresent(String.self, forKey: .id))
            status = try? container.decodeIfPresent(String.self, forKey: .status)
        }
    }

    func snapshot() -> CodexStatusSnapshot {
        let codex = summary.components.filter { $0.name.localizedCaseInsensitiveContains("codex") }
        let components = codex.map { component in
            let affected = summary.affectedComponents.first { $0.id == component.id }
            return CodexStatusComponent(name: component.name, status: Self.status(of: affected))
        }
        return CodexStatusSnapshot(components: components)
    }

    private static func status(of affected: CodexStatusResponse.Affected?) -> ClaudeServiceStatus {
        guard let affected else { return .operational }
        switch affected.status {
        case "full_outage": return .majorOutage
        case .some(let raw):
            let parsed = ClaudeServiceStatus.parse(raw)
            return parsed.isIncident ? parsed : .degradedPerformance
        case .none: return .degradedPerformance
        }
    }
}
