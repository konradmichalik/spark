import AppKit
import SwiftUI

// The redesign's colour system (docs/design/rules.md, "Colour"). Every token resolves per
// appearance, so views never branch on light or dark themselves.

extension NSColor {
    /// A colour that resolves to `light` in Aqua and `dark` in Dark Aqua.
    static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Theme {
    static let paperNS = NSColor.adaptive(light: NSColor(hex: 0xF2F2EF), dark: NSColor(hex: 0x1C1C1B))
    static let cardNS = NSColor.adaptive(light: NSColor(hex: 0xFAFAF8), dark: NSColor(hex: 0x262625))
    static let inkNS = NSColor.adaptive(light: NSColor(hex: 0x111111), dark: NSColor(hex: 0xEDEDE8))
    static let inkSecondaryNS = NSColor.adaptive(light: NSColor(hex: 0x5C5C58), dark: NSColor(hex: 0xA3A39D))
    static let inkTertiaryNS = NSColor.adaptive(light: NSColor(hex: 0x6E6E69), dark: NSColor(hex: 0x8F8F8A))
    static let hairlineNS = NSColor.adaptive(light: NSColor(hex: 0xE4E4DF), dark: NSColor(hex: 0x333331))
    static let dotTrackNS = NSColor.adaptive(
        light: NSColor(hex: 0x111111, alpha: 0.15),
        dark: NSColor(hex: 0xEDEDE8, alpha: 0.16)
    )
    /// Brand red. Not configurable.
    static let accentNS = NSColor.adaptive(light: NSColor(hex: 0xD71921), dark: NSColor(hex: 0xFF5A5F))
    static let warningNS = NSColor.adaptive(light: NSColor(hex: 0xB07800), dark: NSColor(hex: 0xF0B429))
    /// Claude's logo colour. Only for its logo and the faint tint of its selected tab, never data.
    static let claudeLogoNS = NSColor(hex: 0xC96442)

    static let paper = Color(nsColor: paperNS)
    static let card = Color(nsColor: cardNS)
    static let ink = Color(nsColor: inkNS)
    static let inkSecondary = Color(nsColor: inkSecondaryNS)
    static let inkTertiary = Color(nsColor: inkTertiaryNS)
    static let hairline = Color(nsColor: hairlineNS)
    static let dotTrack = Color(nsColor: dotTrackNS)
    static let accent = Color(nsColor: accentNS)
    static let warning = Color(nsColor: warningNS)
    static let claudeLogo = Color(nsColor: claudeLogoNS)
}

/// The colour state of a usage value. Derived in one place so every view agrees.
enum UsageTone: Equatable {
    case normal, warning, critical

    /// Critical is checked first, so thresholds set the wrong way round still flag high values.
    init(value: Double, warning: Double, critical: Double) {
        guard value.isFinite else {
            self = .normal
            return
        }
        if value >= critical {
            self = .critical
        } else if value >= warning {
            self = .warning
        } else {
            self = .normal
        }
    }

    var nsColor: NSColor {
        switch self {
        case .normal: Theme.inkNS
        case .warning: Theme.warningNS
        case .critical: Theme.accentNS
        }
    }

    var color: Color { Color(nsColor: nsColor) }
}
