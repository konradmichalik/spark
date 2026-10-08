// Renders the app icon, the README logo and the website icons from the dot mark.
// Run through `make brand`, or: swift scripts/render-brand-assets.swift <repo-root>
//
// The mark geometry mirrors SparkMark.swift and SparkMarkLayout. The script cannot import the
// app module, so keep these constants identical to the app when the mark changes.

import AppKit

let dotCount = 12
let ringRadiusRatio: CGFloat = 0.35
let dotRatio: CGFloat = 0.10
let centreRatio: CGFloat = 0.16
let faintOpacity: CGFloat = 0.18
let faintPositions: Set<Int> = [9, 10, 11]

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let paper = color(0xF2F2EF)
let card = color(0xFAFAF8)
let hairline = color(0xE4E4DF)
let ink = color(0x111111)
let accent = color(0xD71921)

/// Draws the mark into a square `rect` (bottom-left origin). `dotRatioOverride` thickens the
/// dots for tiny favicons, where 10 % of the side would fall below two pixels.
func drawMark(in rect: CGRect, dotRatioOverride: CGFloat? = nil, centreRatioOverride: CGFloat? = nil) {
    let side = rect.width
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let dot = side * (dotRatioOverride ?? dotRatio)
    let radius = side * ringRadiusRatio
    for position in 0..<dotCount {
        // Clockwise from twelve o'clock in a y-up context.
        let angle = Double(position) / Double(dotCount) * 2 * .pi
        let point = CGPoint(x: center.x + radius * CGFloat(sin(angle)), y: center.y + radius * CGFloat(cos(angle)))
        ink.withAlphaComponent(faintPositions.contains(position) ? faintOpacity : 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: point.x - dot / 2, y: point.y - dot / 2, width: dot, height: dot)).fill()
    }
    let centre = side * (centreRatioOverride ?? centreRatio)
    accent.setFill()
    NSBezierPath(ovalIn: CGRect(x: center.x - centre / 2, y: center.y - centre / 2, width: centre, height: centre)).fill()
}

/// The app icon tile on the macOS grid: an 824 pt body centred on 1024, rounded corners,
/// card fill, hairline edge, soft shadow, mark at 62 % of the body.
func drawTile(canvas: CGFloat) {
    let scale = canvas / 1024
    let body = 824 * scale
    let bodyRect = CGRect(x: (canvas - body) / 2, y: (canvas - body) / 2 + 6 * scale, width: body, height: body)
    let shape = NSBezierPath(roundedRect: bodyRect, xRadius: 185 * scale, yRadius: 185 * scale)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = 20 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
    shadow.set()
    card.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    hairline.setStroke()
    shape.lineWidth = max(1, 2 * scale)
    shape.stroke()

    let mark = body * 0.62
    drawMark(in: CGRect(x: bodyRect.midX - mark / 2, y: bodyRect.midY - mark / 2, width: mark, height: mark))
}

/// Draws into an sRGB bitmap, so the hex colours above land in the PNG unchanged instead of
/// being converted through the display or a generic RGB profile.
func render(size: Int, to path: String, draw: (CGFloat) -> Void) {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let cgContext = CGContext(
              data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        fatalError("Could not create a \(size) px bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cgContext, flipped: false)
    draw(CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    guard let image = cgContext.makeImage(),
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        fatalError("Could not encode \(path)")
    }
    do {
        try data.write(to: URL(fileURLWithPath: path))
    } catch {
        fatalError("Could not write \(path): \(error)")
    }
    print("wrote \(path)")
}

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath

render(size: 1024, to: "\(root)/Spark/Assets.xcassets/AppIcon.appiconset/icon_1024.png", draw: drawTile)
render(size: 1024, to: "\(root)/assets/spark-logo.png", draw: drawTile)
render(size: 1024, to: "\(root)/site/spark-logo.png", draw: drawTile)
render(size: 32, to: "\(root)/site/favicon.png") { side in
    drawMark(in: CGRect(x: 0, y: 0, width: side, height: side), dotRatioOverride: 0.13, centreRatioOverride: 0.2)
}
render(size: 16, to: "\(root)/site/favicon-16.png") { side in
    drawMark(in: CGRect(x: 0, y: 0, width: side, height: side), dotRatioOverride: 0.15, centreRatioOverride: 0.24)
}
render(size: 180, to: "\(root)/site/apple-touch-icon.png") { side in
    paper.setFill()
    CGRect(x: 0, y: 0, width: side, height: side).fill()
    let mark = side * 0.62
    drawMark(in: CGRect(x: (side - mark) / 2, y: (side - mark) / 2, width: mark, height: mark))
}
