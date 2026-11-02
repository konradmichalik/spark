import SwiftUI

/// The row under the report header: on level 1 the provider filter, while both providers count;
/// on level 2 the breadcrumb back to the overview, at the same height (docs/design/rules.md,
/// "Navigation"). Built like the popover's provider tabs and breadcrumb.
struct ReportScopeBar: View {
    @Binding var selection: ReportScope
    @Binding var screen: ReportScreen
    /// The scope the report shows: `selection`, or Claude when there is no filter.
    let scope: ReportScope
    let showsFilter: Bool
    /// The period's fresh tokens of a scope.
    let tokens: (ReportScope) -> Int

    @AppStorage(PopoverHeader.providerTintKey) private var showProviderTint = true
    @Namespace private var selectionSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if screen != .overview {
            breadcrumb
        } else if showsFilter {
            filter
        }
    }

    private var filter: some View {
        HStack(spacing: 2) {
            ForEach(ReportScope.allCases, id: \.self) { segment($0) }
        }
        .padding(2)
        .background(Theme.hairline, in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Provider")
    }

    private func segment(_ option: ReportScope) -> some View {
        let isSelected = option == selection
        let amount = formatTokenCount(tokens(option))
        return Button {
            selection = option
        } label: {
            HStack(spacing: 4) {
                Self.logos(option)
                Text(option.segmentLabel)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(Theme.ink)
                Text(amount)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background {
                // Only the selected background slides (docs/design/rules.md, "Motion": Tabs).
                if isSelected { selectedBackground(option).matchedGeometryEffect(id: "selectedScope", in: selectionSpace) }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.segmentLabel), \(amount) tokens")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectedBackground(_ option: ReportScope) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7)
        return shape.fill(Theme.card)
            .overlay(shape.fill(option == .claude && showProviderTint ? Theme.claudeLogo.opacity(0.12) : .clear))
            .overlay(shape.strokeBorder(Theme.hairline))
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Button {
                screen = .overview
            } label: {
                HStack(spacing: 5) {
                    TablerIconView(.chevronLeft, size: 12, color: Theme.inkSecondary)
                    Self.logos(scope)
                    Text(scope.segmentLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to the overview, \(scope.segmentLabel)")
            Text("/")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkTertiary)
                .accessibilityHidden(true)
            Text(screen.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
        .frame(height: 34)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    /// All leads with both providers' logos, Claude first.
    private static func logos(_ scope: ReportScope) -> some View {
        HStack(spacing: 2) {
            ForEach(ReportScoping.providers(scope), id: \.self) { provider in
                PopoverHeader.logo(for: provider.usageProvider)
            }
        }
    }
}
