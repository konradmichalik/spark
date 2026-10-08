import ServiceManagement
import SwiftUI

struct GeneralTab: View {
    @EnvironmentObject var state: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        SettingsPage {
            SettingsSection(title: "Refresh", footnote: refreshNote) {
                SettingsCard {
                    SettingsRow(title: "Mode") {
                        PaperSegments(selection: refreshModeBinding, options: RefreshModeOption.allCases, label: "Refresh mode")
                    }
                    if state.refreshMode == RefreshModeOption.fixed.rawValue {
                        SettingsDivider()
                        SettingsRow(title: "Interval") {
                            PaperSegments(
                                selection: intervalBinding, options: IntervalOption.refresh, label: "Refresh interval"
                            )
                        }
                    }
                }
            }

            SettingsSection(title: "Startup") {
                SettingsCard {
                    SettingsToggle(title: "Launch at login", subtitle: "Start Spark when your Mac starts.", isOn: $launchAtLogin)
                }
            }
            .onChange(of: launchAtLogin) { applyLaunchAtLogin() }

            SettingsSection(title: "Data export") {
                SettingsCard {
                    SettingsToggle(
                        title: "Export data for other apps",
                        subtitle: "Writes the usage to ~/Library/Application Support/Spark/data.json on every refresh, "
                            + "for example for a Stream Deck plugin.",
                        isOn: $state.exportDataEnabled
                    )
                }
            }
            .onChange(of: state.exportDataEnabled) { state.handleExportDataToggleChanged() }
        }
    }

    private var refreshNote: String {
        guard state.refreshMode != RefreshModeOption.fixed.rawValue else {
            return "Spark asks for your usage at this interval."
        }
        return "Every 5 min while you work, then 10, 15 and 30 min as you go idle. "
            + "Now every \(state.currentRefreshInterval.shortDuration)."
    }

    private var refreshModeBinding: Binding<RefreshModeOption> {
        Binding(
            get: { RefreshModeOption(rawValue: state.refreshMode) ?? .smart },
            set: { state.refreshMode = $0.rawValue }
        )
    }

    private var intervalBinding: Binding<IntervalOption> {
        Binding(
            get: { IntervalOption.matching(state.refreshInterval, in: IntervalOption.refresh) },
            set: {
                state.refreshInterval = $0.seconds
                state.startUsagePolling(interval: $0.seconds)
            }
        )
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin.toggle()
        }
    }
}
