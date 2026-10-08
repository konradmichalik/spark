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

    func testDimmedImageKeepsSizeAndTemplateFlag() {
        let dimmed = MenuBarGlyph(value: 45, tone: .normal).image(logo: nil, alpha: 0.35)
        XCTAssertEqual(dimmed.size, CGSize(width: 16, height: 16))
        XCTAssertTrue(dimmed.isTemplate)
        XCTAssertNotNil(dimmed.cgImage(forProposedRect: nil, context: nil, hints: nil))
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

    func testANewlyFilledDotFadesIn() {
        let faded = MenuBarGlyph.fade(from: [1, 0.28, 0.28], to: [1, 1, 0.64], progress: 0.5)

        XCTAssertEqual(faded, [1, 0.64, 0.46], accuracy: 0.0001)
    }

    func testAFallingDotShowsAtOnce() {
        XCTAssertEqual(MenuBarGlyph.fade(from: [1, 1], to: [1, 0.28], progress: 0), [1, 0.28], accuracy: 0.0001)
    }

    func testFadeFramesEndBeforeTheFullValue() {
        XCTAssertEqual(MenuBarGlyph.fadeSteps, [1.0 / 3, 2.0 / 3])
        XCTAssertEqual(MenuBarGlyph.fadeFrame * (MenuBarGlyph.fadeSteps.count + 1), .milliseconds(252))
    }

    func testAGlyphCanStartPartWayIntoAFade() {
        let glyph = MenuBarGlyph(value: 100, tone: .normal, fadingFrom: 0, progress: 0)

        XCTAssertEqual(glyph.opacities, DotRingLayout.partialOpacities(count: MenuBarGlyph.dotCount, value: 0))
    }
}

private func XCTAssertEqual(_ lhs: [Double], _ rhs: [Double], accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
    for (left, right) in zip(lhs, rhs) {
        XCTAssertEqual(left, right, accuracy: accuracy, file: file, line: line)
    }
}
