import SwiftUI

struct MenuBarTab: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var codex: CodexState

    /// With Codex off there is only one provider to show.
    private var menuBarFootnote: String {
        codex.isActive
            ? "The menu bar shows the provider of the tab you opened last."
            : "The menu bar shows Claude. Turn on Codex in Connections to switch."
    }

    var body: some View {
        SettingsPage {
            SettingsSection(title: "Style") {
                HStack(spacing: 10) {
                    OptionCard(
                        title: "Ring", subtitle: "Twelve dots, one per twelfth",
                        isSelected: MenuBarIconStyle(stored: state.iconStyle) == .ring,
                        preview: { GlyphThumb(logo: nil) },
                        action: { state.iconStyle = MenuBarIconStyle.ring.rawValue }
                    )
                    OptionCard(
                        title: "With logo", subtitle: "The provider's logo before the ring",
                        isSelected: MenuBarIconStyle(stored: state.iconStyle) == .providerLogo,
                        preview: { GlyphThumb(logo: .claude) },
                        action: { state.iconStyle = MenuBarIconStyle.providerLogo.rawValue }
                    )
                }
            }

            SettingsSection(title: "Displayed value", footnote: menuBarFootnote) {
                SettingsCard {
                    SettingsRow(title: "Value", subtitle: "None leaves the ring alone.") {
                        PaperSegments(selection: valueBinding, options: MenuBarValueOption.allCases, label: "Displayed value")
                    }
                }
            }
        }
    }

    private var valueBinding: Binding<MenuBarValueOption> {
        Binding(get: { MenuBarValueOption(stored: state.menuBarValue) }, set: { state.menuBarValue = $0.rawValue })
    }
}

struct DisplayTab: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var codex: CodexState
    @AppStorage("showProviderTabValues") private var showProviderTabValues = true
    @AppStorage(PopoverHeader.providerTintKey) private var showProviderTint = true

    var body: some View {
        SettingsPage {
            SettingsSection(title: "Value display") {
                HStack(spacing: 10) {
                    OptionCard(
                        title: "Bars", subtitle: "Large number, dot bars below",
                        isSelected: state.usageDisplayStyle == "bars",
                        preview: { BarsPreviewThumb() },
                        action: { state.usageDisplayStyle = "bars" }
                    )
                    OptionCard(
                        title: "Ring", subtitle: "Session as a dot ring, week beside it",
                        isSelected: state.usageDisplayStyle != "bars",
                        preview: { RingThumb() },
                        action: { state.usageDisplayStyle = "ring" }
                    )
                }
            }

            SettingsSection(title: "Show in the popover") {
                SettingsCard {
                    SettingsToggle(title: "History", isOn: $state.showGraph)
                    SettingsDivider()
                    SettingsToggle(
                        title: "Session forecast", subtitle: "Where the session lands at the reset, and the burn rate.",
                        isOn: $state.showProjection
                    )
                    SettingsDivider()
                    SettingsToggle(
                        title: "Active sessions", subtitle: "Sessions with activity in the last 5 minutes.", isOn: $state.showActiveSessions
                    )
                    SettingsDivider()
                    SettingsToggle(title: "Statistics", isOn: $state.showStats)
                    SettingsDivider()
                    SettingsToggle(title: "Top projects", subtitle: "On the Statistics screen.", isOn: $state.showProjectBreakdown)
                    SettingsDivider()
                    SettingsToggle(
                        title: "API cost estimate",
                        subtitle: "What the tokens would cost at API list prices, in Statistics and the report. "
                            + "Downloads the public price list from GitHub once a day.",
                        isOn: $state.showApiCost
                    )
                }
            }
            .onChange(of: state.showApiCost) { state.refreshLiveStats() }

            SettingsSection(title: "All limits") {
                SettingsCard {
                    SettingsToggle(title: "Sonnet", subtitle: "Weekly Sonnet limit.", isOn: $state.showSonnetUsage)
                    SettingsDivider()
                    SettingsToggle(title: "Opus", subtitle: "Weekly Opus limit.", isOn: $state.showOpusUsage)
                    SettingsDivider()
                    SettingsToggle(title: "Fable", subtitle: "Weekly Fable limit.", isOn: $state.showFableUsage)
                }
            }

            if codex.isActive {
                SettingsSection(title: "Provider tabs") {
                    SettingsCard {
                        SettingsToggle(title: "Session usage in the tabs", isOn: $showProviderTabValues)
                        SettingsDivider()
                        SettingsToggle(
                            title: "Provider colour in the tabs", subtitle: "A faint tint of the provider's logo colour on its tab.",
                            isOn: $showProviderTint
                        )
                    }
                }
            }
        }
    }
}
