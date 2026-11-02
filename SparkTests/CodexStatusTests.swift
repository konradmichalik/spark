import XCTest
@testable import Spark

final class CodexStatusTests: XCTestCase {

    private func snapshot(affected: String = "[]", extra: String = "") throws -> CodexStatusSnapshot {
        let json = """
        {"summary": {
          "components": [
            {"id": "c1", "name": "Chat Completions"},
            {"id": "c2", "name": "Codex Web"},
            {"id": "c3", "name": "Codex API"},
            {"id": "c4", "name": "Codex in ChatGPT Desktop"}
          ],
          "affected_components": \(affected)\(extra)
        }}
        """
        return try JSONDecoder().decode(CodexStatusResponse.self, from: Data(json.utf8)).snapshot()
    }

    func testKeepsOnlyCodexComponents() throws {
        let result = try snapshot()

        XCTAssertEqual(result.components.map(\.name), ["Codex Web", "Codex API", "Codex in ChatGPT Desktop"])
        XCTAssertEqual(result.overall, .operational)
        XCTAssertEqual(result.description, "Codex: Operational")
    }

    func testIncidentOnAnotherProductLeavesCodexOperational() throws {
        let result = try snapshot(affected: #"[{"component_id": "c1", "status": "full_outage"}]"#)

        XCTAssertEqual(result.overall, .operational)
    }

    func testAffectedCodexComponentSetsTheOverallToTheWorst() throws {
        let result = try snapshot(affected: """
        [{"component_id": "c2", "status": "degraded_performance"}, {"component_id": "c3", "status": "full_outage"}]
        """)

        XCTAssertEqual(result.components.map(\.status), [.degradedPerformance, .majorOutage, .operational])
        XCTAssertEqual(result.overall, .majorOutage)
    }

    func testAffectedEntryWithoutStatusCountsAsDegraded() throws {
        let result = try snapshot(affected: #"[{"component_id": "c2"}]"#)

        XCTAssertEqual(result.overall, .degradedPerformance)
    }

    func testUnexpectedAffectedShapeDoesNotFailTheDecode() throws {
        let result = try snapshot(affected: #""none""#)

        XCTAssertEqual(result.overall, .operational)
    }

    func testMissingAffectedKeyIsOperational() throws {
        let json = #"{"summary": {"components": [{"id": "c2", "name": "Codex Web"}]}}"#
        let result = try JSONDecoder().decode(CodexStatusResponse.self, from: Data(json.utf8)).snapshot()

        XCTAssertEqual(result.overall, .operational)
    }

    func testPageWithoutCodexComponentsIsUnknown() throws {
        let json = #"{"summary": {"components": [{"id": "c1", "name": "Chat Completions"}]}}"#
        let result = try JSONDecoder().decode(CodexStatusResponse.self, from: Data(json.utf8)).snapshot()

        XCTAssertEqual(result.overall, .unknown)
        XCTAssertEqual(result.description, "Status unavailable")
    }

    func testMissingComponentListFailsTheDecode() {
        XCTAssertThrowsError(try JSONDecoder().decode(CodexStatusResponse.self, from: Data(#"{"summary": {}}"#.utf8)))
    }
}
