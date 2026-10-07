import AppKit
import XCTest
@testable import Spark

final class DesignTokensTests: XCTestCase {
    private func resolved(_ color: NSColor, in name: NSAppearance.Name) -> NSColor? {
        var result: NSColor?
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            result = color.usingColorSpace(.sRGB)
        }
        return result
    }

    private func assertHex(_ color: NSColor?, _ hex: UInt32, file: StaticString = #filePath, line: UInt = #line) {
        guard let color else { return XCTFail("colour did not resolve", file: file, line: line) }
        XCTAssertEqual(color.redComponent, CGFloat((hex >> 16) & 0xFF) / 255, accuracy: 0.003, file: file, line: line)
        XCTAssertEqual(color.greenComponent, CGFloat((hex >> 8) & 0xFF) / 255, accuracy: 0.003, file: file, line: line)
        XCTAssertEqual(color.blueComponent, CGFloat(hex & 0xFF) / 255, accuracy: 0.003, file: file, line: line)
    }

    func testTokensResolvePerAppearance() {
        assertHex(resolved(Theme.paperNS, in: .aqua), 0xF2F2EF)
        assertHex(resolved(Theme.paperNS, in: .darkAqua), 0x1C1C1B)
        assertHex(resolved(Theme.inkNS, in: .aqua), 0x111111)
        assertHex(resolved(Theme.inkNS, in: .darkAqua), 0xEDEDE8)
        assertHex(resolved(Theme.accentNS, in: .aqua), 0xD71921)
        assertHex(resolved(Theme.accentNS, in: .darkAqua), 0xFF5A5F)
        assertHex(resolved(Theme.warningNS, in: .aqua), 0xB07800)
        assertHex(resolved(Theme.warningNS, in: .darkAqua), 0xF0B429)
    }

    func testDotTrackIsTranslucentInk() {
        XCTAssertEqual(resolved(Theme.dotTrackNS, in: .aqua)?.alphaComponent ?? 0, 0.15, accuracy: 0.003)
        XCTAssertEqual(resolved(Theme.dotTrackNS, in: .darkAqua)?.alphaComponent ?? 0, 0.16, accuracy: 0.003)
    }

    func testToneFollowsThresholds() {
        XCTAssertEqual(UsageTone(value: 74.9, warning: 75, critical: 90), .normal)
        XCTAssertEqual(UsageTone(value: 75, warning: 75, critical: 90), .warning)
        XCTAssertEqual(UsageTone(value: 90, warning: 75, critical: 90), .critical)
        XCTAssertEqual(UsageTone(value: 140, warning: 75, critical: 90), .critical)
    }

    func testToneWithSwappedThresholdsPrefersCritical() {
        XCTAssertEqual(UsageTone(value: 85, warning: 90, critical: 80), .critical)
    }

    func testToneForNonFiniteValueIsNormal() {
        XCTAssertEqual(UsageTone(value: .nan, warning: 75, critical: 90), .normal)
        XCTAssertEqual(UsageTone(value: -.infinity, warning: 75, critical: 90), .normal)
    }
}
