import XCTest
@testable import Spark

final class ModelRowTests: XCTestCase {
    func testFamilyRowListsItsVersionsLargestFirstWithDatedIdsMerged() throws {
        let rows = ModelRow.rows(from: [
            "claude-opus-5-1": 100,
            "claude-opus-5-5": 400,
            "claude-opus-4-5-20251101": 50,
            "claude-opus-4-5": 10,
            "claude-sonnet-5-5": 7
        ])

        let opus = try XCTUnwrap(rows.first { $0.family == .opus })
        XCTAssertEqual(opus.tokens, 560)
        XCTAssertEqual(opus.versions.map(\.label), ["Opus 5.5", "Opus 5.1", "Opus 4.5"])
        XCTAssertEqual(opus.versions.map(\.tokens), [400, 100, 60])
    }

    func testFamilyCostKeepsAModelThatOnlyReadFromCache() throws {
        let rows = ModelRow.rows(
            from: ["claude-opus-5-5": 1_000, "claude-opus-5-1": 0],
            costByModel: ["claude-opus-5-5": 2.0, "claude-opus-5-1": 0.5]
        )

        XCTAssertEqual(try XCTUnwrap(rows.first?.cost), 2.5, accuracy: 1e-9)
    }

    func testVersionSummaryIncludesCostWhenKnown() throws {
        let rows = ModelRow.rows(
            from: ["claude-opus-5-5": 2_000_000, "claude-opus-5-1": 1_000],
            costByModel: ["claude-opus-5-5": 12.5]
        )

        let opus = try XCTUnwrap(rows.first)
        XCTAssertEqual(opus.versionSummary, "Opus 5.5 · 2.0M · $12.50\nOpus 5.1 · 1.0K")
    }
}
