import AppKit
import SwiftUI

// MARK: - Status Row

/// A Claude incident: the status in ink beside an ochre status icon, and a link to the status
/// page when Claude Code itself is affected.
struct StatusRow: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 8) {
            TablerIconView(state.status.icon, size: 14, color: Theme.warning)
            Text("Claude: \(state.status.displayName)")
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink)
            Spacer()
            if !state.claudeCodeStatus.isHealthy {
                Link(destination: URL(staticString: "https://status.claude.com")) {
                    HStack(spacing: 3) {
                        Text("Code: \(state.claudeCodeStatus.displayName)")
                            .font(.system(size: 11))
                        TablerIconView(.externalLink, size: 10, color: Theme.inkSecondary)
                    }
                    .foregroundStyle(Theme.inkSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline))
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
