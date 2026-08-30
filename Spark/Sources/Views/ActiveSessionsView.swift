import AppKit
import SwiftUI

/// Sessions with a transcript write in the last few minutes — see `ActiveSessionResolver`. Its
/// own section, not nested inside `StatsRow`'s card: everything in the Stats card is scoped to
/// the selected Today/7d/30d/All period, while this list is not, so nesting it there would
/// falsely imply the period selector applies here too. Keeping it out of Stats also avoids
/// putting this count next to Stats' own "Sessions" line, where two different session numbers
/// would sit side by side meaning different things.
///
/// Deliberately quiet: no "active now" label repeated on every row — that would just restate what
/// the section title already says. A row's trailing column stays empty until that session
/// actually starts aging. The count sits in the header's accessory slot as plain monospaced text,
/// not a badge: the uppercase header title now separates this from the rows beneath it, so the
/// capsule that used to compensate for that isn't needed.
struct ActiveSessionsView: View {
    let sessions: [ActiveSession]

    /// Beyond this many rows, collapse to a "+N more" line rather than growing the popover
    /// without bound — kept low since, unlike Top Projects, this section is always expanded.
    private static let visibleLimit = 4

    /// Only the overflow beyond `visibleLimit` is gated behind a tap, not the whole section — the
    /// common case stays fully glanceable with no interaction at all. No collapse-back-down
    /// control: with this few extra rows, a second tap to hide them again isn't worth the
    /// affordance.
    @State private var showAll = false

    private static let density = SectionDensity.compact

    var body: some View {
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: Self.density.headerGap) {
                header
                SectionCard(density: Self.density) {
                    ForEach(sessions.prefix(visibleCount)) { session in
                        ActiveSessionRow(session: session)
                    }
                    if !showAll, sessions.count > Self.visibleLimit {
                        Button {
                            showAll = true
                        } label: {
                            Text("+\(sessions.count - Self.visibleLimit) more")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var visibleCount: Int {
        showAll ? sessions.count : Self.visibleLimit
    }

    private var header: some View {
        SectionHeader(title: "Active Sessions", icon: .terminal2, density: Self.density) {
            Text("\(sessions.count)")
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
        }
        .help("Sessions with activity in the last 5 minutes")
    }
}

private struct ActiveSessionRow: View {
    let session: ActiveSession

    var body: some View {
        // A `Button` rather than `.onTapGesture` — see `ProjectBreakdownDisclosure.header` for
        // why (keyboard focus and VoiceOver activation, which a tap gesture doesn't provide).
        // Only interactive when `cwd` is known: `displayName`'s key-derived fallback isn't a real
        // path, so there'd be nothing to reveal or copy.
        if let cwd = session.cwd {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)])
            } label: {
                content
            }
            .buttonStyle(.plain)
            .help("Reveal \(cwd) in Finder")
            .contextMenu {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)])
                }
                Button("Open in Terminal") {
                    openInTerminal(cwd)
                }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cwd, forType: .string)
                }
            }
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 5) {
            // Colors by freshness rather than sitting at a constant color, so it carries actual
            // per-row information instead of just repeating "this section is about active
            // sessions" — orange while hot, fading to secondary once a row starts aging.
            Circle()
                .fill(session.isFresh() ? Theme.sparkOrange : Color.secondary.opacity(0.4))
                .frame(width: 6, height: 6)

            Text(session.displayName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)

            // Secondary weight so the hex recedes behind the project name it disambiguates.
            if let suffix = session.sessionIdSuffix {
                Text(suffix)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let trailing = trailingText {
                Text(trailing)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    /// Context size normally stands alone (`"142K"`) — the status dot already carries
    /// fresh-vs-aging, so repeating that as a word next to it would be redundant on almost every
    /// row. The elapsed time only rejoins it, appended, once a row is actually aging: at that
    /// point it's new information (exactly how stale), not a restatement of the dot.
    private var trailingText: String? {
        let context = session.contextTokens.map(formatTokenCount)
        guard let age = session.activityLabel() else { return context }
        guard let context else { return age }
        return "\(context) · \(age)"
    }
}

/// Launches Terminal.app at `path` via `/usr/bin/open`, rather than shelling out through `zsh -c`
/// (see `CLIVersionClient.readLocalVersion`) — arguments passed as an array need no shell
/// quoting, so a project path containing spaces can't break this. Fire-and-forget: nothing here
/// needs the launched process's exit status.
private func openInTerminal(_ path: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-a", "Terminal", path]
    try? process.run()
}
