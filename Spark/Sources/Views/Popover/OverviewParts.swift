import AppKit
import SwiftUI

/// A card on paper: the card fill with a hairline outline (docs/design/rules.md, "Layout").
struct PaperCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        content()
            .background(Theme.card, in: shape)
            .overlay(shape.strokeBorder(Theme.hairline))
    }
}

/// The last six hours as dot columns. The whole card opens the history; hovering reads out the
/// exact values.
struct HistoryCard: View {
    let columns: [HistoryColumn]
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            PaperCard {
                VStack(alignment: .leading, spacing: 8) {
                    header
                    DotColumnsChart(columns: columns) { HistoryHover.text(for: $0, in: columns) }
                        .frame(height: 56)
                        .accessibilityHidden(true)
                    HistoryAxisLabels(labels: HistoryAxis.labels(items: HistoryLayout.items(columns), columns: columns))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("History, last 6 hours")
        .accessibilityHint("Opens the history")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("History").font(.system(size: 12.5)).foregroundStyle(Theme.ink)
            Spacer()
            HistoryLegend()
            TablerIconView(.chevronRight, size: 11, color: Theme.inkTertiary)
        }
    }
}

/// Session as a grey dot, week as a red stroke: the two series told apart by shape.
struct HistoryLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Circle().fill(Theme.ink.opacity(0.4)).frame(width: 5, height: 5)
                Text("Session")
            }
            HStack(spacing: 4) {
                Capsule().fill(Theme.accent).frame(width: 10, height: 2)
                Text("Week")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.inkSecondary)
        .accessibilityHidden(true)
    }
}

/// First, middle and last label under a dot column graph.
struct HistoryAxisLabels: View {
    let labels: [String]

    var body: some View {
        HStack {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                if index > 0 { Spacer() }
                Text(label)
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(Theme.inkTertiary)
        .accessibilityHidden(true)
    }
}

/// One row of the overview's row group: a label, a short value and a chevron.
struct OverviewRow: Identifiable {
    enum Icon {
        case pulse(isLive: Bool)
        case dots(DotIcon)
    }

    let screen: PopoverScreen
    let icon: Icon
    let label: String
    let value: String?
    var id: PopoverScreen { screen }
}

struct OverviewRows: View {
    let rows: [OverviewRow]
    let onOpen: (PopoverScreen) -> Void

    var body: some View {
        PaperCard {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }
                    rowButton(row)
                }
            }
        }
    }

    private func rowButton(_ row: OverviewRow) -> some View {
        Button {
            onOpen(row.screen)
        } label: {
            HStack(spacing: 10) {
                switch row.icon {
                case .pulse(let isLive): PulsingDot(isLive: isLive)
                case .dots(let icon): DotIconView(icon: icon)
                }
                Text(row.label).font(.system(size: 12.5)).foregroundStyle(Theme.ink)
                Spacer()
                if let value = row.value {
                    Text(value)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSecondary)
                }
                TablerIconView(.chevronRight, size: 11, color: Theme.inkTertiary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.value.map { "\(row.label), \($0)" } ?? row.label)
    }
}

/// The overview's footer: the update time is the refresh button, quit on the right.
struct PopoverFooter: View {
    let lastUpdated: Date?
    let isLoading: Bool
    let onRefresh: () -> Void

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 5 { return "just now" }
        if interval < 60 { return "\(Int(interval))s ago" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        return "\(Int(interval / 3600))h ago"
    }

    static func statusText(isLoading: Bool, lastUpdated: Date?, now: Date = Date()) -> String {
        if isLoading { return "Updating\u{2026}" }
        guard let lastUpdated else { return "Not updated yet" }
        return "Updated \(relative(lastUpdated, now: now))"
    }

    var body: some View {
        HStack {
            Button(action: onRefresh) {
                HStack(spacing: 6) {
                    TablerIconView(.refresh, size: 13, color: Theme.inkSecondary)
                    Text(Self.statusText(isLoading: isLoading, lastUpdated: lastUpdated))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .frame(minHeight: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(isLoading)
            .accessibilityLabel(isLoading ? "Refreshing" : "Refresh")
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                TablerIconView(.power, size: 14, color: Theme.inkSecondary, isDecorative: false)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .tooltip("Quit")
            .accessibilityLabel("Quit Spark")
        }
    }
}
