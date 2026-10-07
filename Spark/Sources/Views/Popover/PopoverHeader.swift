import SwiftUI

/// One provider tab: its logo and name, the session value next to them, and a tooltip with the
/// plan and sign-in path.
struct ProviderTab: Identifiable {
    let provider: UsageProvider
    let value: Double?
    let tone: UsageTone
    let tooltip: String?
    var id: UsageProvider { provider }
}

/// The header of every popover screen (docs/design/rules.md, "Navigation"). Row 1 never
/// changes; row 2 holds the provider tabs on the overview and a breadcrumb on detail screens,
/// at the same height so navigating does not shift the layout.
struct PopoverHeader: View {
    let provider: UsageProvider
    @Binding var screen: PopoverScreen
    let showTabs: Bool
    let tabs: [ProviderTab]
    let isLoading: Bool
    let onSelect: (UsageProvider) -> Void
    let onReport: () -> Void

    /// The Claude logo colour, used only for its own logo and the faint tint of its tab.
    static let claudeColor = Color(red: 0.788, green: 0.392, blue: 0.259)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            brandRow
            if screen != .overview {
                breadcrumb
            } else if showTabs {
                tabRow
            }
        }
    }

    private var brandRow: some View {
        HStack(spacing: 8) {
            SparkMark(size: 18, isLoading: isLoading)
            Text("spark")
                .font(.doto(size: 19, weight: 800))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button(action: onReport) {
                headerIcon(.calendarMonth)
            }
            .buttonStyle(.borderless)
            .tooltip("Usage report")
            .accessibilityLabel("Usage report")
            SettingsLink {
                headerIcon(.settings)
            }
            .buttonStyle(.borderless)
            .tooltip("Settings")
            .accessibilityLabel("Settings")
        }
    }

    private func headerIcon(_ icon: TablerIcon) -> some View {
        TablerIconView(icon, size: 15, color: Theme.inkSecondary, isDecorative: false)
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
    }

    private var tabRow: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                tabButton(tab)
            }
        }
        .padding(2)
        .background(Theme.hairline, in: RoundedRectangle(cornerRadius: 9))
    }

    private func tabButton(_ tab: ProviderTab) -> some View {
        let isSelected = tab.provider == provider
        let percent = tab.value.map { UsageFormat.percent($0) }
        return Button {
            onSelect(tab.provider)
        } label: {
            HStack(spacing: 4) {
                Self.logo(for: tab.provider)
                Text(tab.provider.segmentLabel)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(Theme.ink)
                if let percent {
                    Text(percent)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(tab.tone == .normal ? Theme.inkSecondary : tab.tone.color)
                }
            }
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background { if isSelected { selectedBackground(for: tab.provider) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tooltip(tab.tooltip)
        .accessibilityLabel([tab.provider.segmentLabel, percent].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(tab.tooltip ?? "")
    }

    private func selectedBackground(for provider: UsageProvider) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7)
        return shape.fill(Theme.card)
            .overlay(shape.fill(provider == .claude ? Self.claudeColor.opacity(0.12) : .clear))
            .overlay(shape.strokeBorder(Theme.hairline))
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Button {
                screen = .overview
            } label: {
                HStack(spacing: 5) {
                    TablerIconView(.chevronLeft, size: 12, color: Theme.inkSecondary)
                    Self.logo(for: provider)
                    Text(provider.segmentLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to \(provider.segmentLabel)")
            Text("/")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkTertiary)
                .accessibilityHidden(true)
            Text(screen.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
        }
        .frame(height: 34)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    static func logo(for provider: UsageProvider) -> some View {
        Group {
            switch provider {
            case .claude:
                ClaudeLogoShape().fill(claudeColor)
            case .codex:
                TablerIconView(.brandOpenai, size: 13, color: Theme.ink)
            }
        }
        .frame(width: 13, height: 13)
        .accessibilityHidden(true)
    }
}
