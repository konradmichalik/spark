import XCTest
import AppKit
@testable import Spark

final class TablerIconTests: XCTestCase {

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
}
