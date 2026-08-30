import XCTest
import AppKit
@testable import Spark

final class TablerIconTests: XCTestCase {

    /// Guards one direction: every `TablerIcon` case has a bundled asset behind it. Catches a
    /// case added without running `scripts/fetch-tabler-icons.sh` (or a typo in the raw value),
    /// which would otherwise render as an empty frame at runtime.
    func testEveryIconResolvesToABundledAsset() {
        for icon in TablerIcon.allCases {
            XCTAssertNotNil(
                NSImage(named: icon.assetName),
                "Missing asset for TablerIcon.\(icon) (expected \(icon.assetName).imageset)"
            )
        }
    }

    func testEveryIconIsATemplateImage() {
        for icon in TablerIcon.allCases {
            let image = NSImage(named: icon.assetName)
            XCTAssertEqual(
                image?.isTemplate, true,
                "\(icon.assetName) must be a template image so it can be tinted"
            )
        }
    }

    /// Guards the other direction: every `.imageset` actually checked into the asset catalog has
    /// a `TablerIcon` case pointing at it. Catches an asset left behind after a case is renamed or
    /// removed by hand — the bundle-loading test above can't see this, since a stale asset nobody
    /// references still loads fine, it just never ships a reason to exist.
    ///
    /// Reads the checked-in directory rather than the built bundle: the bundle only contains what
    /// `Contents.json` already wired up, which is exactly the thing an orphan slipped past, so the
    /// directory listing is the only source of truth that can actually catch it.
    func testNoOrphanedImagesetHasNoMatchingIconCase() throws {
        let iconsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SparkTests/
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("Spark/Assets.xcassets/Icons")

        let entries = try FileManager.default.contentsOfDirectory(atPath: iconsDirectory.path)
        let imagesetNames = entries
            .filter { $0.hasSuffix(".imageset") }
            .map { String($0.dropLast(".imageset".count)) }

        let knownAssetNames = Set(TablerIcon.allCases.map(\.assetName))

        for name in imagesetNames {
            XCTAssertTrue(
                knownAssetNames.contains(name),
                "\(name).imageset has no matching TablerIcon case — add the case or delete the orphaned asset"
            )
        }
    }
}
