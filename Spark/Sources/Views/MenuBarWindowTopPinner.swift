import AppKit
import SwiftUI

/// Keeps the `MenuBarExtra`'s `.window`-style host window anchored at a fixed top-left corner
/// while it's open. That style doesn't preserve the window's top edge when its SwiftUI content
/// grows or shrinks — expanding "Top Projects" or switching the History graph mode both change
/// content height, and AppKit's default resize keeps the frame anchored in a way that pushes the
/// top edge upward as height increases. Since this window already sits at the very top of the
/// screen, that drift can push the header off-screen entirely. Re-asserting the top-left corner
/// after every resize undoes the drift without touching the width/height the resize already set.
private final class TopPinningView: NSView {
    private var pinnedTopLeft: NSPoint?
    private var resizeObserver: NSObjectProtocol?
    private var keyObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeObservers()
        guard let window else { return }

        pinnedTopLeft = window.frame.topLeft

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            // Deferred to the next run-loop turn rather than applied inline: an animated SwiftUI
            // resize fires this notification repeatedly as it progresses, so an inline
            // correction already wins there, but a resize that happens as a single instant snap
            // (no explicit `withAnimation` around the state change that triggered it) can have a
            // second, later positioning pass from AppKit's own layout that overwrites an inline
            // correction before the frame is actually drawn. Reasserting one tick later wins
            // that race instead of losing it.
            DispatchQueue.main.async {
                guard let self, let window, let pinnedTopLeft = self.pinnedTopLeft else { return }
                window.setFrameTopLeftPoint(pinnedTopLeft)
            }
        }

        // The `.window`-style host window is reused across show/hide cycles rather than
        // recreated, so `viewDidMoveToWindow` only fires once — re-anchoring here on every
        // fresh appearance means each popover opening gets its own correct baseline instead of
        // being pinned forever to wherever the window happened to sit the very first time.
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let self, let window else { return }
            self.pinnedTopLeft = window.frame.topLeft
        }
    }

    private func removeObservers() {
        [resizeObserver, keyObserver].forEach { observer in
            observer.map(NotificationCenter.default.removeObserver)
        }
        resizeObserver = nil
        keyObserver = nil
    }

    deinit {
        removeObservers()
    }
}

private extension NSRect {
    var topLeft: NSPoint { NSPoint(x: minX, y: maxY) }
}

/// Zero-size, invisible view that exists only to hook into `viewDidMoveToWindow` — see
/// `TopPinningView`. Add via `.background(MenuBarWindowTopPinner())` on the content passed to
/// `MenuBarExtra`.
struct MenuBarWindowTopPinner: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        TopPinningView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
