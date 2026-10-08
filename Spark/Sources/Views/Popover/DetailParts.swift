import AppKit
import SwiftUI

/// A large number in Doto with its unit and prefix in SF Pro (docs/design/rules.md,
/// "Typography"). Shrinks rather than truncates when a value is wider than its tile.
struct DotoValue: View {
    let parts: NumberParts
    var prefix: String?
    var size: CGFloat = 30
    var color: Color = Theme.ink

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            if let prefix {
                Text(prefix).font(.system(size: size * 0.42, weight: .semibold))
            }
            Text(parts.number).font(.doto(size: size))
            if !parts.unit.isEmpty {
                Text(parts.unit).font(.system(size: size * 0.42, weight: .semibold))
            }
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

/// A label over a Doto value, with an optional explaining tooltip.
struct StatFact: View {
    let label: String
    let parts: NumberParts
    var prefix: String?
    var tooltip: String?
    /// Read by VoiceOver instead of the split number, e.g. "about 117 dollars".
    var spokenValue: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkSecondary)
                if tooltip != nil {
                    Spacer(minLength: 0)
                    TablerIconView(.helpCircle, size: 11, color: Theme.inkTertiary)
                }
            }
            DotoValue(parts: parts, prefix: prefix)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .tooltip(tooltip, title: label, delay: .quick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spokenValue ?? [prefix, parts.number, parts.unit].compactMap { $0 }.joined(separator: " "))
        .accessibilityHint(tooltip ?? "")
    }
}

/// A short explanation under a detail screen's content.
struct DetailNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The row that expands a long list in place.
struct ShowMoreRow: View {
    let more: ShowMore
    @Binding var isExpanded: Bool

    var body: some View {
        if let label = more.label(expanded: isExpanded) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 5) {
                    Text(label)
                    TablerIconView(.chevronRight, size: 10, color: Theme.inkTertiary)
                        .rotationEffect(.degrees(isExpanded ? -90 : 90))
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: .infinity, minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

extension View {
    /// Reveal in Finder, Open in Terminal and Copy Path for a row that stands for a folder.
    @ViewBuilder
    func pathActions(_ path: String?) -> some View {
        if let path {
            contextMenu {
                Button("Reveal in Finder") { PathActions.reveal(path) }
                Button("Open in Terminal") { PathActions.openInTerminal(path) }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                }
            }
        } else {
            self
        }
    }
}

enum PathActions {
    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Runs `/usr/bin/open` with the path as an argument, not through a shell, so a path with
    /// spaces needs no quoting.
    static func openInTerminal(_ path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", path]
        try? process.run()
    }
}
