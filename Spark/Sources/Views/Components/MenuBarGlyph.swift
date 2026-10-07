import AppKit
import SwiftUI

/// The provider mark drawn in front of the ring in the "with logo" style.
enum MenuBarLogo: Equatable {
    case claude, codex
}

/// The menu bar glyph: twelve dots on a 16pt ring, each one a twelfth, the last partial dot at
/// proportional opacity (docs/design/rules.md, "Menu bar"). A template image unless the value
/// reached the warning or critical threshold.
struct MenuBarGlyph: Equatable {
    static let dotCount = 12
    static let ringSize = CGSize(width: 16, height: 16)
    private static let dotDiameter: CGFloat = 2.8
    private static let logoWidth: CGFloat = 12
    private static let logoGap: CGFloat = 2

    let opacities: [Double]
    let tone: UsageTone

    init(value: Double, tone: UsageTone) {
        opacities = DotRingLayout.partialOpacities(count: Self.dotCount, value: value)
        self.tone = tone
    }

    var isTemplate: Bool { tone == .normal }

    func size(logo: MenuBarLogo?) -> CGSize {
        guard logo != nil else { return Self.ringSize }
        return CGSize(width: Self.logoWidth + Self.logoGap + Self.ringSize.width, height: Self.ringSize.height)
    }

    func image(logo: MenuBarLogo?) -> NSImage {
        let base: NSColor = isTemplate ? .black : tone.nsColor
        let opacities = opacities
        let image = NSImage(size: size(logo: logo), flipped: true) { rect in
            let ringOriginX = rect.width - Self.ringSize.width
            if let logo {
                Self.drawLogo(logo, in: CGRect(x: 0, y: 2, width: Self.logoWidth, height: Self.logoWidth), color: base)
            }
            let center = CGPoint(x: ringOriginX + Self.ringSize.width / 2, y: Self.ringSize.height / 2)
            let radius = Self.ringSize.width / 2 - Self.dotDiameter / 2 - 0.4
            for (point, opacity) in zip(DotRingLayout.points(count: Self.dotCount, radius: radius, center: center), opacities) {
                base.withAlphaComponent(opacity).setFill()
                let half = Self.dotDiameter / 2
                NSBezierPath(ovalIn: CGRect(x: point.x - half, y: point.y - half, width: Self.dotDiameter, height: Self.dotDiameter)).fill()
            }
            return true
        }
        image.isTemplate = isTemplate
        return image
    }

    private static func drawLogo(_ logo: MenuBarLogo, in rect: CGRect, color: NSColor) {
        switch logo {
        case .claude:
            let path = NSBezierPath(cgPath: ClaudeLogoShape().path(in: rect).cgPath)
            color.setFill()
            path.fill()
        case .codex:
            guard let symbol = NSImage(named: TablerIcon.brandOpenai.assetName) else { return }
            symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            color.setFill()
            rect.fill(using: .sourceAtop)
        }
    }
}

/// The two glyph styles in Settings > Menu Bar. Stored in `@AppStorage("iconStyle")`; values
/// from earlier versions ("logo", "dot", "bar", "minimal") all fall back to the ring.
enum MenuBarIconStyle: String {
    case ring, providerLogo

    init(stored: String) {
        self = MenuBarIconStyle(rawValue: stored) ?? .ring
    }
}
