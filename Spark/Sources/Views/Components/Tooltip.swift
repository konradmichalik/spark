import SwiftUI

// A tooltip drawn inside the window instead of the system `.help()` one: it matches the
// existing hover tooltips (`RingTooltip`), honours Reduce Transparency, and is positioned against
// the window so it can never be cut off at the edge of the menu bar popover. A view using
// `.tooltip` needs a `.tooltipHost()` on one of its ancestors, which draws the bubble.

enum TooltipLayout {
    static let gap: CGFloat = 4
    static let inset: CGFloat = 6
    static let maxWidth: CGFloat = 220

    /// Top-left corner for a tooltip of `size`: centered below `anchor`, flipped above it when
    /// there is no room below, and kept `inset` away from every edge of `container`.
    static func origin(anchor: CGRect, size: CGSize, container: CGSize) -> CGPoint {
        let maxX = max(inset, container.width - size.width - inset)
        let x = min(max(anchor.midX - size.width / 2, inset), maxX)

        let below = anchor.maxY + gap
        let fitsBelow = below + size.height <= container.height - inset
        let preferredY = fitsBelow ? below : anchor.minY - gap - size.height
        let maxY = max(inset, container.height - size.height - inset)
        let y = min(max(preferredY, inset), maxY)

        return CGPoint(x: x, y: y)
    }
}

extension View {
    /// Shows `text` after a short hover, like the system tooltip, with an optional bold `title`
    /// above it. Nothing is shown when both are `nil` or empty.
    func tooltip(_ text: String?, title: String? = nil) -> some View {
        modifier(TooltipModifier(title: title.flatMap { $0.isEmpty ? nil : $0 }, text: text.flatMap { $0.isEmpty ? nil : $0 }))
    }

    /// Draws the tooltips requested by `.tooltip` on views inside it. Apply once per window root.
    func tooltipHost() -> some View {
        modifier(TooltipHostModifier())
    }

    /// The bubble behind a tooltip, shared with `RingTooltip` so both look the same. The border
    /// and shadow lift it off the popover, whose material it would otherwise blend into.
    func tooltipChrome(reduceTransparency: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        return adaptiveBackground(reduceTransparency: reduceTransparency, in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
    }
}

// MARK: - Plumbing

private enum TooltipHost {
    static let space = "tooltipHost"
    /// Matches the system tooltip, so a pointer just passing over a control stays quiet.
    static let delay: Duration = .milliseconds(500)
}

private struct TooltipRequest: Equatable {
    let title: String?
    let text: String?
    let anchor: CGRect
}

private struct TooltipRequestKey: PreferenceKey {
    static let defaultValue: TooltipRequest? = nil

    static func reduce(value: inout TooltipRequest?, nextValue: () -> TooltipRequest?) {
        value = nextValue() ?? value
    }
}

private struct TooltipSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct TooltipModifier: ViewModifier {
    let title: String?
    let text: String?

    @State private var isShown = false
    @State private var showTask: Task<Void, Never>?

    @ViewBuilder
    func body(content: Content) -> some View {
        if title != nil || text != nil {
            content
                .onHover { hovering in
                    hovering ? scheduleShow() : hide()
                }
                .simultaneousGesture(TapGesture().onEnded { hide() })
                .onDisappear { hide() }
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TooltipRequestKey.self,
                            value: isShown
                                ? TooltipRequest(title: title, text: text, anchor: proxy.frame(in: .named(TooltipHost.space)))
                                : nil
                        )
                    }
                )
        } else {
            content
        }
    }

    private func scheduleShow() {
        showTask?.cancel()
        showTask = Task { @MainActor in
            try? await Task.sleep(for: TooltipHost.delay)
            guard !Task.isCancelled else { return }
            isShown = true
        }
    }

    private func hide() {
        showTask?.cancel()
        showTask = nil
        isShown = false
    }
}

private struct TooltipHostModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: TooltipHost.space)
            .overlayPreferenceValue(TooltipRequestKey.self) { request in
                GeometryReader { proxy in
                    if let request {
                        TooltipBubble(request: request, container: proxy.size)
                    }
                }
                .allowsHitTesting(false)
            }
    }
}

private struct TooltipBubble: View {
    let request: TooltipRequest
    let container: CGSize

    @State private var size: CGSize = .zero
    @AppStorage("reduceTransparency") private var reduceTransparency: Bool = false

    var body: some View {
        let origin = TooltipLayout.origin(anchor: request.anchor, size: size, container: container)

        VStack(alignment: .leading, spacing: 3) {
            if let title = request.title {
                Text(title)
                    .fontWeight(.medium)
            }
            if let text = request.text {
                Text(text)
                    .foregroundStyle(request.title == nil ? .primary : .secondary)
            }
        }
        .font(.caption2)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: TooltipLayout.maxWidth, alignment: .leading)
        .padding(6)
        .tooltipChrome(reduceTransparency: reduceTransparency)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: TooltipSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(TooltipSizeKey.self) { size = $0 }
        // Hidden until measured, otherwise it flashes at the wrong spot for one frame.
        .opacity(size == .zero ? 0 : 1)
        .offset(x: origin.x, y: origin.y)
        .accessibilityHidden(true)
    }
}
