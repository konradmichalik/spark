import AppKit
import SwiftUI

/// Heights the report reports about itself: the scrolled content and the visible scroll area.
struct ReportContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct ReportVisibleHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Resizes the report window so the whole report shows without scrolling, keeping its top edge
/// in place and never growing past the screen (`ReportLayout.windowHeight`). Runs when the
/// content height changes, so a manual resize stands until the report changes.
struct ReportWindowFitter: NSViewRepresentable {
    let content: CGFloat
    let visible: CGFloat

    private static let minimumHeight: CGFloat = 420

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        let content = content
        let visible = visible
        Task { @MainActor in
            guard content > 0, visible > 0, let window = nsView.window, let screen = window.screen else { return }
            let target = ReportLayout.windowHeight(
                current: window.frame.height, visibleScroll: visible, content: content,
                screenHeight: screen.visibleFrame.height, minimum: Self.minimumHeight
            )
            guard abs(target - window.frame.height) > 1 else { return }
            var frame = window.frame
            frame.origin.y += frame.height - target
            frame.size.height = target
            frame.origin.y = max(frame.origin.y, screen.visibleFrame.minY)
            window.setFrame(frame, display: true, animate: false)
        }
    }
}
