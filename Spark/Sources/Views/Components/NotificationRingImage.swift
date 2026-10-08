import AppKit

extension NotificationRing {
    private static let pixelSide = 128

    /// The ring as a 64pt PNG at 2x, on a card tile so it reads on any notification background.
    /// `appearance` resolves the light or dark token values.
    func pngData(appearance: NSAppearance?) -> Data? {
        let side = Self.pixelSide
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        if let appearance {
            appearance.performAsCurrentDrawingAppearance { draw(in: rect) }
        } else {
            draw(in: rect)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    private func draw(in rect: CGRect) {
        Theme.cardNS.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.width * 0.22).fill()

        let dot = rect.width * 0.1
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width * 0.34
        let track = DotRingLayout.partialOpacities(count: 1, value: 0).first ?? 0
        let points = DotRingLayout.points(count: MenuBarGlyph.dotCount, radius: radius, center: center)
        for (point, opacity) in zip(points, opacities) {
            // The layout runs clockwise with y growing downwards; this context grows upwards.
            let mirrored = CGPoint(x: point.x, y: 2 * center.y - point.y)
            let fill = opacity > track ? tone.nsColor.withAlphaComponent(opacity) : Theme.dotTrackNS
            fill.setFill()
            NSBezierPath(ovalIn: CGRect(x: mirrored.x - dot / 2, y: mirrored.y - dot / 2, width: dot, height: dot)).fill()
        }

        let text = NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: rect.width * 0.2, weight: .bold),
            .foregroundColor: tone.nsColor
        ])
        let size = text.size()
        text.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
    }
}
