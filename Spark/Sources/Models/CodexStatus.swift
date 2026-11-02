import Foundation

// MARK: - Codex Status

struct ServiceComponent: Equatable {
    let name: String
    let status: ClaudeServiceStatus
}

/// What Spark knows about the Codex parts of the OpenAI status page. The page also lists the
/// API and ChatGPT, which an incident may hit without touching Codex, so only the components
/// of the Codex group and the ones named Codex count.
struct CodexStatusSnapshot: Equatable {
    let components: [ServiceComponent]

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
    private let summary: StatusPageSummary

    func snapshot() -> CodexStatusSnapshot {
        let codex = summary.components.filter {
            summary.codexGroupIDs.contains($0.id) || $0.name.range(of: "codex", options: .caseInsensitive) != nil
        }
        let components = codex.map { component in
            let affected = summary.affectedComponents.first { $0.id == component.id }
            return ServiceComponent(name: component.name, status: Self.status(of: affected))
        }
        return CodexStatusSnapshot(components: components)
    }

    private static func status(of affected: StatusPageAffected?) -> ClaudeServiceStatus {
        guard let affected else { return .operational }
        switch affected.status {
        case "full_outage": return .majorOutage
        case .some(let raw):
            let parsed = ClaudeServiceStatus.parse(raw)
            if parsed.isHealthy { return .operational }
            return parsed.isIncident ? parsed : .degradedPerformance
        case .none: return .degradedPerformance
        }
    }
}

private struct StatusPageSummary: Decodable {
    let components: [StatusPageComponent]
    let affectedComponents: [StatusPageAffected]
    let codexGroupIDs: Set<String>

    enum CodingKeys: String, CodingKey {
        case components, structure
        case affectedComponents = "affected_components"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        components = try container.decode([StatusPageComponent].self, forKey: .components)
        affectedComponents = (try? container.decodeIfPresent([StatusPageAffected].self, forKey: .affectedComponents)) ?? []
        let structure = try? container.decodeIfPresent(StatusPageStructure.self, forKey: .structure)
        codexGroupIDs = structure?.codexComponentIDs ?? []
    }
}

private struct StatusPageComponent: Decodable {
    let id: String
    let name: String
}

/// The page's groups. The Codex group holds the CLI and the VS Code extension, whose names
/// do not mention Codex.
private struct StatusPageStructure: Decodable {
    let items: [StatusPageItem]

    var codexComponentIDs: Set<String> {
        let groups = items.compactMap(\.group).filter { $0.name.caseInsensitiveCompare("Codex") == .orderedSame }
        return Set(groups.flatMap { $0.components.map(\.componentId) })
    }
}

private struct StatusPageItem: Decodable {
    let group: StatusPageGroup?
}

private struct StatusPageGroup: Decodable {
    let name: String
    let components: [StatusPageMember]
}

private struct StatusPageMember: Decodable {
    let componentId: String

    enum CodingKeys: String, CodingKey { case componentId = "component_id" }
}

/// The component id and impact of one affected component. Both keys are guesses from
/// incident.io's API, so an entry that lacks them still counts as degraded.
private struct StatusPageAffected: Decodable {
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
