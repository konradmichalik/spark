import XCTest
@testable import Spark

final class ModelFamilyTests: XCTestCase {

    // MARK: - Family grouping

    func testSonnetModelGroupsAsSonnet() {
        XCTAssertEqual(ModelFamily.family(forRawModelId: "claude-sonnet-5"), .sonnet)
    }

    func testOpusModelGroupsAsOpus() {
        XCTAssertEqual(ModelFamily.family(forRawModelId: "claude-opus-4-6"), .opus)
    }

    func testFableModelGroupsAsFable() {
        XCTAssertEqual(ModelFamily.family(forRawModelId: "claude-fable-5"), .fable)
    }

    func testHaikuModelGroupsAsOther() {
        XCTAssertEqual(ModelFamily.family(forRawModelId: "claude-haiku-4-5"), .other)
    }

    func testUnrecognizedModelGroupsAsOther() {
        XCTAssertEqual(ModelFamily.family(forRawModelId: "some-future-model"), .other)
    }

    func testFamilyGroupingIsCaseInsensitive() {
        XCTAssertEqual(ModelFamily.family(forRawModelId: "Claude-Opus-5"), .opus)
    }

    // MARK: - Display name normalization

    func testDisplayNameFormatsVersionWithDots() {
        XCTAssertEqual(ModelFamily.displayName(forRawModelId: "claude-opus-4-6"), "Opus 4.6")
    }

    func testDisplayNameFormatsSingleVersionSegment() {
        XCTAssertEqual(ModelFamily.displayName(forRawModelId: "claude-sonnet-5"), "Sonnet 5")
    }

    func testDisplayNameFallsBackToRawIdWhenNotClaudePrefixed() {
        XCTAssertEqual(ModelFamily.displayName(forRawModelId: "some-future-model"), "some-future-model")
    }

    func testDisplayNameFallsBackToRawIdForSyntheticMarker() {
        XCTAssertEqual(ModelFamily.displayName(forRawModelId: "<synthetic>"), "<synthetic>")
    }

    func testDisplayNameFallsBackToRawIdWhenVersionSegmentIsNotNumeric() {
        XCTAssertEqual(ModelFamily.displayName(forRawModelId: "claude-opus-preview"), "claude-opus-preview")
    }
}
