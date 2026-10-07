import AppKit
import SwiftUI

// MARK: - Status Row

struct StatusRow: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack {
            TablerIconView(state.status.icon, size: 13, color: Theme.sparkOrange)
            Text("Claude: \(state.status.displayName)")
                .font(.caption)

            Spacer()

            if !state.claudeCodeStatus.isHealthy, let statusPage = URL(string: "https://status.claude.com") {
                Link(destination: statusPage) {
                    HStack(spacing: 2) {
                        Text("Code: \(state.claudeCodeStatus.displayName)")
                            .font(.caption2)
                        TablerIconView(.externalLink, size: 9, color: Theme.sparkOrange)
                    }
                    .foregroundColor(Theme.sparkOrange)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Window Resizer

/// Measures the SwiftUI content size via GeometryReader and forces the
/// hosting NSPanel to match, working around the MenuBarExtra resize bug.
struct WindowResizer: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onChange(of: proxy.size) { _, newSize in
                    resizeHostingWindow(to: newSize)
                }
                .onAppear {
                    resizeHostingWindow(to: proxy.size)
                }
        }
    }

    private func resizeHostingWindow(to size: CGSize) {
        DispatchQueue.main.async {
            guard let panel = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible }) else { return }
            let contentRect = panel.contentRect(forFrameRect: panel.frame)
            let deltaHeight = size.height - contentRect.size.height
            var frame = panel.frame
            frame.origin.y -= deltaHeight
            frame.size.height += deltaHeight
            panel.setFrame(frame, display: true)
        }
    }
}
