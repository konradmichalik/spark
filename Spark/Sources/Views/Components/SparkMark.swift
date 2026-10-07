import SwiftUI

/// The brand mark: twelve dots on a circle, nine filled, three faint, a red centre dot
/// (docs/design/rules.md, "Brand"). While loading, the faint gap steps clockwise.
enum SparkMarkLayout {
    static let dotCount = 12
    static let faintOpacity = 0.18

    /// Opacity per dot, clockwise from twelve o'clock. At step 0 the gap sits on dots 9 to 11.
    static func opacities(step: Int) -> [Double] {
        let shift = ((step % dotCount) + dotCount) % dotCount
        return (0..<dotCount).map { position in
            let fromGap = (position - (9 + shift) % dotCount + dotCount) % dotCount
            return fromGap < 3 ? faintOpacity : 1
        }
    }
}

struct SparkMark: View {
    enum Style { case mark, tile }

    let size: CGFloat
    var isLoading = false
    var style: Style = .mark

    @State private var step = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch style {
            case .mark:
                dots(in: size)
            case .tile:
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .fill(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).strokeBorder(Theme.hairline))
                    .overlay(dots(in: size * 0.72))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: isLoading && !reduceMotion) {
            guard isLoading, !reduceMotion else {
                step = 0
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(110))
                step += 1
            }
        }
    }

    private func dots(in side: CGFloat) -> some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let dot = side * 0.1
            let points = DotRingLayout.points(count: SparkMarkLayout.dotCount, radius: side * 0.35, center: center)
            for (point, opacity) in zip(points, SparkMarkLayout.opacities(step: step)) {
                let rect = CGRect(x: point.x - dot / 2, y: point.y - dot / 2, width: dot, height: dot)
                context.fill(Path(ellipseIn: rect), with: .color(Theme.ink.opacity(opacity)))
            }
            let centre = side * 0.16
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - centre / 2, y: center.y - centre / 2, width: centre, height: centre)),
                with: .color(Theme.accent)
            )
        }
        .frame(width: side, height: side)
    }
}
