import AppKit
import CoreText
import XCTest
@testable import Spark

final class DotoFontTests: XCTestCase {
    private func weight(of font: NSFont) -> Double? {
        let axis = NSNumber(value: 0x7767_6874)
        let variation = CTFontCopyVariation(font as CTFont) as? [NSNumber: NSNumber]
        if let value = variation?[axis] {
            return value.doubleValue
        }
        // CoreText omits an axis that sits at its default, so read the default from the axes.
        let axes = CTFontCopyVariationAxes(font as CTFont) as? [[String: Any]] ?? []
        let match = axes.first { ($0[kCTFontVariationAxisIdentifierKey as String] as? NSNumber) == axis }
        return (match?[kCTFontVariationAxisDefaultValueKey as String] as? NSNumber)?.doubleValue
    }

    func testBundledFontIsRegistered() {
        XCTAssertNotNil(NSFont(name: Doto.fontName, size: 12))
    }

    func testWeightIsAppliedToTheVariableAxis() {
        XCTAssertEqual(weight(of: Doto.nsFont(size: 20, weight: 400)) ?? 0, 400, accuracy: 1)
        XCTAssertEqual(weight(of: Doto.nsFont(size: 20)) ?? 0, 900, accuracy: 1)
    }

    func testWeightIsClampedToTheAxisRange() {
        XCTAssertEqual(weight(of: Doto.nsFont(size: 20, weight: 2000)) ?? 0, 900, accuracy: 1)
        XCTAssertEqual(weight(of: Doto.nsFont(size: 20, weight: 10)) ?? 0, 100, accuracy: 1)
    }

    func testMissingFontFallsBackToMonospacedSystemFont() {
        let font = Doto.nsFont(named: "NoSuchFont-Regular", size: 20, weight: 900)
        XCTAssertEqual(font.pointSize, 20)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.monoSpace) || font.isFixedPitch)
    }
}
