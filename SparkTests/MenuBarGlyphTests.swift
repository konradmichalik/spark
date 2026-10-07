import AppKit
import XCTest
@testable import Spark

final class MenuBarGlyphTests: XCTestCase {
    func testTwelveDotsWithAPartialLastDot() {
        let glyph = MenuBarGlyph(value: 45, tone: .normal)
        XCTAssertEqual(glyph.opacities.count, 12)
        XCTAssertEqual(Array(glyph.opacities.prefix(5)), Array(repeating: 1, count: 5))
        XCTAssertGreaterThan(glyph.opacities[5], 0.28)
        XCTAssertLessThan(glyph.opacities[5], 1)
    }

    func testFortyFiveAndFiftyLookDifferent() {
        XCTAssertNotEqual(MenuBarGlyph(value: 45, tone: .normal).opacities, MenuBarGlyph(value: 50, tone: .normal).opacities)
    }

    func testOverHundredIsAFullRing() {
        XCTAssertEqual(MenuBarGlyph(value: 140, tone: .critical).opacities, Array(repeating: 1, count: 12))
    }

    func testOnlyWarningAndCriticalLeaveTheTemplate() {
        XCTAssertTrue(MenuBarGlyph(value: 10, tone: .normal).isTemplate)
        XCTAssertFalse(MenuBarGlyph(value: 80, tone: .warning).isTemplate)
        XCTAssertFalse(MenuBarGlyph(value: 95, tone: .critical).isTemplate)
    }

    func testImageSizeAndTemplateFlag() {
        let plain = MenuBarGlyph(value: 45, tone: .normal).image(logo: nil)
        XCTAssertEqual(plain.size, CGSize(width: 16, height: 16))
        XCTAssertTrue(plain.isTemplate)

        let withLogo = MenuBarGlyph(value: 92, tone: .critical).image(logo: .claude)
        XCTAssertEqual(withLogo.size, CGSize(width: 30, height: 16))
        XCTAssertFalse(withLogo.isTemplate)
    }

    func testImageDrawsWithoutCrashingForEveryLogo() {
        for logo in [MenuBarLogo?.none, .claude, .codex] {
            let image = MenuBarGlyph(value: 45, tone: .normal).image(logo: logo)
            XCTAssertNotNil(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        }
    }

    func testEveryOldIconStyleMapsToTheRing() {
        for stored in ["logo", "dot", "bar", "minimal", "ring", "", "unexpected"] {
            XCTAssertEqual(MenuBarIconStyle(stored: stored), .ring, stored)
        }
        XCTAssertEqual(MenuBarIconStyle(stored: "providerLogo"), .providerLogo)
    }
}
