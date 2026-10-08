import AppKit
import SwiftUI

/// A card on the overview that opens a detail screen as a whole (docs/design/rules.md, "Navigation").
private struct OverviewCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        content()
            .background(Theme.card, in: shape)
            .overlay(shape.strokeBorder(Theme.hairline))
    }
}

/// The last six hours: session as grey dot columns, week as a red line on the same scale.
/// The whole card opens the history.
struct HistoryCard: View {
    let columns: [HistoryColumn]
    let axisLabels: [String]
    let onOpen: () -> Void

    @State private var hovered: Int?

    private static let chartHeight: CGFloat = 56

    var body: some View {
        Button(action: onOpen) {
            OverviewCard {
                VStack(alignment: .leading, spacing: 8) {
                    header
                    chart
                    axis
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
            HStack(spacing: 4) {
                Circle().fill(Theme.ink.opacity(0.4)).frame(width: 5, height: 5)
                Text("Session")
            }
            HStack(spacing: 4) {
                Capsule().fill(Theme.accent).frame(width: 10, height: 2)
                Text("Week")
            }
            TablerIconView(.chevronRight, size: 11, color: Theme.inkTertiary)
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.inkSecondary)
    }

    private var chart: some View {
        GeometryReader { proxy in
            Canvas { context, size in draw(in: &context, size: size) }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hovered = HistoryHover.index(x: location.x, width: proxy.size.width, columns: columns)
                    case .ended:
                        hovered = nil
                    }
                }
                .overlay(alignment: .topLeading) { readout(width: proxy.size.width) }
        }
        .frame(height: Self.chartHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        guard !columns.isEmpty else { return }
        let pitch = size.width / CGFloat(columns.count)
        let dot = min(4, pitch - 1.5)
        let highlighted = hovered ?? columns.lastIndex { $0.session != nil }
        if let hovered {
            let guideX = pitch * (CGFloat(hovered) + 0.5)
            context.fill(Path(CGRect(x: guideX - 0.5, y: 0, width: 1, height: size.height)), with: .color(Theme.hairline))
        }
        for (index, column) in columns.enumerated() {
            guard let session = column.session else { continue }
            let rows = Int((min(max(session, 0), 100) / 100 * Double(size.height / 6)).rounded())
            let colour = index == highlighted ? Theme.ink : Theme.ink.opacity(0.3)
            let centerX = pitch * (CGFloat(index) + 0.5)
            for row in 0..<max(rows, 1) {
                let centerY = size.height - 3 - CGFloat(row) * 6
                context.fill(Path(ellipseIn: CGRect(x: centerX - dot / 2, y: centerY - dot / 2, width: dot, height: dot)), with: .color(colour))
            }
        }
        var line = Path()
        for (index, column) in columns.enumerated() {
            guard let weekly = column.weekly else { continue }
            let point = CGPoint(x: pitch * (CGFloat(index) + 0.5), y: size.height * (1 - min(max(weekly, 0), 100) / 100))
            if line.isEmpty { line.move(to: point) } else { line.addLine(to: point) }
        }
        context.stroke(line, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
    }

    /// Shown at once, without the tooltip delay, beside the hovered column and on the side with
    /// more room, so it never covers the column it describes.
    @ViewBuilder
    private func readout(width: CGFloat) -> some View {
        if let hovered, let text = HistoryHover.text(columns[hovered]) {
            let columnX = width / CGFloat(columns.count) * (CGFloat(hovered) + 0.5)
            let onLeft = columnX > width / 2
            VStack(alignment: .leading, spacing: 2) {
                Text(text.title)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.paper.opacity(0.65))
                Text(text.body)
                    .font(.system(size: 11))
                    .monospacedDigit()
            }
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .tooltipChrome()
            .padding(onLeft ? .trailing : .leading, onLeft ? width - columnX + 8 : columnX + 8)
            .frame(width: width, alignment: onLeft ? .trailing : .leading)
        }
    }

    private var axis: some View {
        HStack {
            ForEach(Array(axisLabels.enumerated()), id: \.offset) { index, label in
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
    let screen: PopoverScreen
    let label: String
    let value: String?
    var id: PopoverScreen { screen }
}

struct OverviewRows: View {
    let rows: [OverviewRow]
    let onOpen: (PopoverScreen) -> Void

    var body: some View {
        OverviewCard {
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
    let lastUpdated: Date
    let isLoading: Bool
    let onRefresh: () -> Void

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 5 { return "just now" }
        if interval < 60 { return "\(Int(interval))s ago" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        return "\(Int(interval / 3600))h ago"
    }

    var body: some View {
        HStack {
            Button(action: onRefresh) {
                HStack(spacing: 6) {
                    TablerIconView(.refresh, size: 13, color: Theme.inkSecondary)
                    Text(isLoading ? "Updating\u{2026}" : "Updated \(Self.relative(lastUpdated))")
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
