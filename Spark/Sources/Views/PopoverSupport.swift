import AppKit
import SwiftUI

// MARK: - Status Row

/// A Claude incident: the status in ink beside an ochre status icon, and a link to the status
/// page when Claude Code itself is affected.
struct StatusRow: View {
    @ObservedObject var state: AppState

    /// A major outage is the one status that earns red; anything milder stays ochre.
    private var tone: UsageTone {
        state.status == .majorOutage || state.claudeCodeStatus == .majorOutage ? .critical : .warning
    }

    var body: some View {
        Link(destination: URL(staticString: "https://status.claude.com")) {
            HStack(spacing: 8) {
                DotIconView(icon: worst.dotIcon, size: 14, color: tone.color)
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
        .tooltip(detail, title: "Claude status")
        .accessibilityLabel(headline)
        .accessibilityHint("Opens status.claude.com")
    }

    private var worst: ClaudeServiceStatus {
        state.status.isIncident ? state.status : state.claudeCodeStatus
    }

    private var headline: String {
        let description = state.statusDescription.trimmingCharacters(in: .whitespaces)
        return state.status.isIncident && !description.isEmpty ? description : "Claude Code: \(worst.displayName)"
    }

    private var detail: String {
        "Claude Code: \(state.claudeCodeStatus.displayName)\nAPI: \(state.apiStatus.displayName)\nOpens status.claude.com"
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
