import SwiftUI

/// One settings tab: paper background, sections spaced by whitespace (board 10).
struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content() }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.paper)
    }
}

/// A titled group with an optional note underneath.
struct SettingsSection<Content: View>: View {
    let title: String
    var footnote: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .accessibilityAddTraits(.isHeader)
            content()
            if let footnote {
                SettingsNote(text: footnote)
            }
        }
    }
}

/// Rows on one card. Rows are separated with `SettingsDivider`, the only hairline inside a card.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: shape)
            .overlay(shape.strokeBorder(Theme.hairline))
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }
}

/// Title, optional subtitle, and a trailing control.
struct SettingsRow<Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 12) {
            SettingsLabel(title: title, subtitle: subtitle)
            Spacer(minLength: 8)
            accessory()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
    }
}

struct SettingsLabel: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A row with an ink switch on the right. The visible label is hidden from VoiceOver because
/// the switch carries the same label.
struct SettingsToggle: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.ink)
                .accessibilityHint(subtitle ?? "")
        }
        .accessibilityElement(children: .contain)
    }
}

/// Secondary text under a card.
struct SettingsNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A shell command to copy, set in mono on a hairline chip.
struct CommandText: View {
    let command: String

    init(_ command: String) {
        self.command = command
    }

    var body: some View {
        Text(command)
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Theme.hairline, in: RoundedRectangle(cornerRadius: 4))
            .textSelection(.enabled)
    }
}

/// A choice shown as a preview card, the selected one outlined in ink (board 10).
struct OptionCard<Preview: View>: View {
    let title: String
    var subtitle: String?
    let isSelected: Bool
    @ViewBuilder var preview: () -> Preview
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        Button(action: action) {
            HStack(spacing: 12) {
                preview()
                    .frame(width: 60, height: 44)
                SettingsLabel(title: title, subtitle: subtitle)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .background(Theme.card, in: shape)
            .overlay(shape.strokeBorder(isSelected ? Theme.ink : Theme.hairline, lineWidth: isSelected ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle ?? "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The status dot on a connection card: ink when connected, red when the sign-in expired, ochre
/// when none was found, an empty track when switched off. The status text always says the same.
struct ConnectionDot: View {
    let state: ConnectionState

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch state {
        case .connected: Theme.ink
        case .expired: Theme.accent
        case .notFound: Theme.warning
        case .off: Theme.dotTrack
        }
    }
}
