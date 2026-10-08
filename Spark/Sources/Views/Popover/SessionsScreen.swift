import SwiftUI

/// The Active Sessions screen (board 5): one row per session with a live dot, how long ago it
/// wrote and its context size. Session ID and model sit in the row's tooltip; a click reveals
/// the project in Finder and the context menu offers the other folder actions.
struct SessionsScreen: View {
    let sessions: [ActiveSession]

    @State private var isExpanded = false

    private static let visibleLimit = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if sessions.isEmpty {
                DetailNote(text: "No active sessions.")
            } else {
                let more = ShowMore(total: sessions.count, limit: Self.visibleLimit)
                PaperCard {
                    VStack(spacing: 0) {
                        let visible = sessions.prefix(more.visibleCount(expanded: isExpanded))
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, session in
                            if index > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                            SessionRow(session: session)
                        }
                        if more.isNeeded {
                            Rectangle().fill(Theme.hairline).frame(height: 1)
                            ShowMoreRow(more: more, isExpanded: $isExpanded)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            DetailNote(text: "Active means a transcript write in the last 5 minutes. Hover a row for its session ID and model.")
        }
    }
}

private struct SessionRow: View {
    let session: ActiveSession

    @State private var isHovered = false

    var body: some View {
        let tooltip = ActiveSessionText.tooltip(session)
        Group {
            if let cwd = session.cwd {
                Button { PathActions.reveal(cwd) } label: { content }
                    .buttonStyle(.plain)
                    .accessibilityHint("Reveals \(cwd) in Finder")
            } else {
                content
            }
        }
        .pathActions(session.cwd)
        .onHover { isHovered = $0 }
        .tooltip(tooltip.body, title: tooltip.title)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ActiveSessionText.accessibilityLabel(session))
        .accessibilityValue("\(tooltip.title). \(tooltip.body)")
    }

    private var content: some View {
        HStack(spacing: 10) {
            PulsingDot(isLive: session.isFresh())
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(session.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let suffix = session.sessionIdSuffix {
                        Text(suffix)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
                Text(ActiveSessionText.subtitle(session))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 8)
            if let context = session.contextTokens {
                Text(formatTokenCount(context))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.ink)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(isHovered ? Theme.dotTrack.opacity(0.35) : .clear)
        .contentShape(Rectangle())
    }
}
