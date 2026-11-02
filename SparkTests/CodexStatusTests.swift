import XCTest
@testable import Spark

final class CodexStatusTests: XCTestCase {

    private func decode(_ json: String) throws -> CodexStatusSnapshot {
        try JSONDecoder().decode(CodexStatusResponse.self, from: Data(json.utf8)).snapshot()
    }

    private func snapshot(affected: String = "[]") throws -> CodexStatusSnapshot {
        try decode("""
        {"summary": {
          "components": [
            {"id": "c1", "name": "Chat Completions"},
            {"id": "c2", "name": "Codex Web"},
            {"id": "c3", "name": "Codex API"},
            {"id": "c4", "name": "CLI"},
            {"id": "c5", "name": "VS Code extension"},
            {"id": "c6", "name": "Codex in ChatGPT Desktop"},
            {"id": "c7", "name": "Login"}
          ],
          "structure": {"items": [
            {"group": {"name": "APIs", "components": [{"component_id": "c1"}, {"component_id": "c7"}]}},
            {"group": {"name": "ChatGPT", "components": [{"component_id": "c6"}]}},
            {"group": {"name": "Codex", "components": [
              {"component_id": "c2"}, {"component_id": "c3"}, {"component_id": "c4"}, {"component_id": "c5"}
            ]}}
          ]},
          "affected_components": \(affected)
        }}
        """)
    }

    func testKeepsTheCodexGroupAndTheComponentsNamedCodex() throws {
        let result = try snapshot()

        XCTAssertEqual(
            Set(result.components.map(\.name)),
            ["Codex Web", "Codex API", "CLI", "VS Code extension", "Codex in ChatGPT Desktop"]
        )
        XCTAssertEqual(result.overall, .operational)
        XCTAssertEqual(result.description, "Codex: Operational")
    }

    func testOutageOfTheCLIAloneIsSeen() throws {
        let result = try snapshot(affected: #"[{"component_id": "c4", "status": "full_outage"}]"#)

        XCTAssertEqual(result.overall, .majorOutage)
    }

    func testIncidentOnAnotherProductLeavesCodexOperational() throws {
        let result = try snapshot(affected: #"[{"component_id": "c1", "status": "full_outage"}]"#)

        XCTAssertEqual(result.overall, .operational)
    }

    func testAffectedCodexComponentSetsTheOverallToTheWorst() throws {
        let result = try snapshot(affected: """
        [{"component_id": "c2", "status": "degraded_performance"}, {"component_id": "c3", "status": "full_outage"}]
        """)

        XCTAssertEqual(result.components.first { $0.name == "Codex Web" }?.status, .degradedPerformance)
        XCTAssertEqual(result.components.first { $0.name == "Codex API" }?.status, .majorOutage)
        XCTAssertEqual(result.overall, .majorOutage)
    }

    func testRecoveredEntryStillListedIsOperational() throws {
        let result = try snapshot(affected: #"[{"component_id": "c2", "status": "operational"}]"#)

        XCTAssertEqual(result.overall, .operational)
    }

    func testUnknownImpactWordCountsAsDegraded() throws {
        let result = try snapshot(affected: #"[{"component_id": "c2", "status": "investigating"}]"#)

        XCTAssertEqual(result.overall, .degradedPerformance)
    }

    func testAffectedEntryWithoutStatusCountsAsDegraded() throws {
        let result = try snapshot(affected: #"[{"component_id": "c2"}]"#)

        XCTAssertEqual(result.overall, .degradedPerformance)
    }

    func testUnexpectedAffectedShapeDoesNotFailTheDecode() throws {
        let result = try snapshot(affected: #""none""#)

        XCTAssertEqual(result.overall, .operational)
    }

    func testWithoutStructureTheNameDecides() throws {
        let result = try decode(#"{"summary": {"components": [{"id": "c2", "name": "Codex Web"}, {"id": "c1", "name": "Login"}]}}"#)

        XCTAssertEqual(result.components.map(\.name), ["Codex Web"])
    }

    func testPageWithoutCodexComponentsIsUnknown() throws {
        let result = try decode(#"{"summary": {"components": [{"id": "c1", "name": "Chat Completions"}]}}"#)

        XCTAssertEqual(result.overall, .unknown)
        XCTAssertEqual(result.description, "Status unavailable")
    }

    func testMissingComponentListFailsTheDecode() {
        XCTAssertThrowsError(try JSONDecoder().decode(CodexStatusResponse.self, from: Data(#"{"summary": {}}"#.utf8)))
    }
}
