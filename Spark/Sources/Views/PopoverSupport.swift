import AppKit
import SwiftUI

// MARK: - Status Row

/// A provider incident: the status in ink beside an ochre status icon, and a link to the
/// provider's status page.
struct StatusRow: View {
    let status: ClaudeServiceStatus
    let headline: String
    let detail: String
    let title: String
    let url: StaticString

    var body: some View {
        Link(destination: URL(staticString: url)) {
            HStack(spacing: 8) {
                StatusDotView(dot: status.dot, size: 14)
                Text(headline)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Spacer(minLength: 4)
                TablerIconView(.externalLink, size: 11, color: Theme.inkSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 40)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tooltip(detail, title: title)
        .accessibilityLabel(headline)
        .accessibilityHint("Opens \(URL(staticString: url).host ?? "the status page")")
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
