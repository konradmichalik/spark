import AppKit
import CoreText
import SwiftUI

/// The bundled variable Doto font (OFL, google/fonts). Large numbers and the wordmark only,
/// see docs/design/rules.md, "Typography".
enum Doto {
    static let fontName = "Doto-Black"
    /// The `wght` variation axis tag as a four-character code.
    private static let weightAxis = NSNumber(value: 0x7767_6874)

    static func nsFont(size: CGFloat, weight: CGFloat = 900) -> NSFont {
        nsFont(named: fontName, size: size, weight: weight)
    }

    /// Falls back to the monospaced system font when `named` is not registered, so a
    /// broken bundle degrades to readable numbers instead of an unstyled glyph run.
    static func nsFont(named: String, size: CGFloat, weight: CGFloat) -> NSFont {
        guard let base = NSFont(name: named, size: size) else {
            return .monospacedSystemFont(ofSize: size, weight: .bold)
        }
        let clamped = min(max(weight, 100), 900)
        let descriptor = base.fontDescriptor.addingAttributes([
            NSFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String):
                [weightAxis: NSNumber(value: Double(clamped))]
        ])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
}

extension Font {
    static func doto(size: CGFloat, weight: CGFloat = 900) -> Font {
        Font(Doto.nsFont(size: size, weight: weight) as CTFont)
    }
}
