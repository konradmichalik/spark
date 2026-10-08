import SwiftUI

// A tooltip drawn inside the window instead of the system `.help()` one: it matches the
// graph readouts, and is positioned against the window so it can never be cut off at the edge
// of the menu bar popover. A view using
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

    /// Width of the tooltip text: its unwrapped width, rounded up so it never wraps by a
    /// fraction, and wrapped at `maxWidth` when it is longer.
    static func textWidth(ideal: CGFloat) -> CGFloat {
        min(max(ideal, 0).rounded(.up), maxWidth)
    }
}

extension View {
    /// Shows `text` after a short hover, like the system tooltip, with an optional bold `title`
    /// above it. Nothing is shown when both are `nil` or empty.
    func tooltip(_ text: String?, title: String? = nil, delay: TooltipDelay = .standard) -> some View {
        modifier(TooltipModifier(
            title: title.flatMap { $0.isEmpty ? nil : $0 }, text: text.flatMap { $0.isEmpty ? nil : $0 }, delay: delay.duration
        ))
    }

    /// A tooltip whose hover target reaches `reach` points above and below the view, without
    /// taking that space in the layout.
    func tooltipTarget(_ text: String?, title: String? = nil, reach: CGFloat, delay: TooltipDelay = .quick) -> some View {
        padding(.vertical, reach)
            .contentShape(Rectangle())
            .tooltip(text, title: title, delay: delay)
            .padding(.vertical, -reach)
    }

    /// Draws the tooltips requested by `.tooltip` on views inside it. Apply once per window root.
    func tooltipHost() -> some View {
        modifier(TooltipHostModifier())
    }

    /// The bubble behind a tooltip, shared with the graph readouts so both look the same: ink
    /// background, paper text (docs/design/rules.md, "Tooltips"). Opaque, so it needs no
    /// Reduce Transparency variant.
    func tooltipChrome() -> some View {
        let shape = RoundedRectangle(cornerRadius: 7)
        return background(Theme.ink, in: shape)
            .foregroundStyle(Theme.paper)
            .shadow(color: .black.opacity(0.22), radius: 9, y: 3)
    }
}

/// How long the pointer rests before a tooltip shows (docs/design/rules.md, "Motion").
enum TooltipDelay {
    /// Long enough that a pointer passing over a control stays quiet.
    case standard
    /// For data marks whose tooltip is the explanation the user is looking for.
    case quick

    var duration: Duration {
        switch self {
        case .standard: .milliseconds(400)
        case .quick: .milliseconds(150)
        }
    }
}

// MARK: - Plumbing

private enum TooltipHost {
    static let space = "tooltipHost"
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

    /// Skips `.zero`: subtrees that never set the key (the border overlay, for one) report the
    /// default, and taking it last-wins would hide the bubble forever.
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

private struct TooltipModifier: ViewModifier {
    let title: String?
    let text: String?
    let delay: Duration

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
            try? await Task.sleep(for: delay)
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

private struct TooltipTextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TooltipBubble: View {
    let request: TooltipRequest
    let container: CGSize

    @State private var size: CGSize = .zero
    @State private var idealTextWidth: CGFloat = 0
    @State private var hasRisen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isMeasured: Bool { size != .zero && idealTextWidth != 0 }
    /// Fades in and rises 4 pt once measured; under Reduce Motion it is simply there. It hides
    /// at once, the host removes it.
    private var isRisen: Bool { reduceMotion || hasRisen }

    var body: some View {
        let origin = TooltipLayout.origin(anchor: request.anchor, size: size, container: container)

        text
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: TooltipLayout.textWidth(ideal: idealTextWidth), alignment: .leading)
            // An unwrapped copy measures the text, so a short tooltip shrinks to it.
            .background(
                text.fixedSize().hidden().background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: TooltipTextWidthKey.self, value: proxy.size.width)
                    }
                )
            )
            .onPreferenceChange(TooltipTextWidthKey.self) { idealTextWidth = $0 }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .tooltipChrome()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: TooltipSizeKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(TooltipSizeKey.self) { size = $0 }
            // Hidden until measured, otherwise it flashes at the wrong spot or width for one frame.
            .opacity(isMeasured && isRisen ? 1 : 0)
            .offset(x: origin.x, y: origin.y + (isRisen ? 0 : 4))
            .onChange(of: isMeasured) {
                guard isMeasured, !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.12)) { hasRisen = true }
            }
            .accessibilityHidden(true)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let title = request.title {
                Text(title.uppercased())
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Theme.paper.opacity(0.65))
            }
            if let text = request.text {
                Text(text)
                    .font(.system(size: 11))
                    .monospacedDigit()
            }
        }
        .multilineTextAlignment(.leading)
    }
}
