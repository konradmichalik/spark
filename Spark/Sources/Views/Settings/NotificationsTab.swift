import SwiftUI
@preconcurrency import UserNotifications

struct NotificationsTab: View {
    @EnvironmentObject var state: AppState
    @State private var testSent = false
    @State private var permissionStatus = "Checking…"
    @State private var permissionDenied = false

    var body: some View {
        SettingsPage {
            SettingsSection(title: "Notifications") {
                SettingsCard {
                    SettingsToggle(
                        title: "Notifications", subtitle: "High usage, resets and status changes.", isOn: $state.notificationsEnabled
                    )
                    SettingsDivider()
                    permissionRow
                }
            }
            .onAppear { checkPermission() }
            .onChange(of: state.notificationsEnabled) {
                if state.notificationsEnabled { requestAndCheck() }
            }

            Group {
                SettingsSection(title: "Thresholds", footnote: thresholdNote) {
                    SettingsCard {
                        thresholdRow(title: "Warning", value: $state.warningThreshold, range: 50...90, tint: Theme.warning)
                        SettingsDivider()
                        thresholdRow(title: "Critical", value: $state.criticalThreshold, range: 75...100, tint: Theme.accent)
                    }
                }

                SettingsSection(title: "Events") {
                    SettingsCard {
                        SettingsToggle(title: "Usage reset", isOn: $state.notifyOnReset)
                        SettingsDivider()
                        SettingsToggle(title: "Claude status incidents", isOn: $state.notifyOnStatusChange)
                        SettingsDivider()
                        SettingsToggle(title: "New Spark version", isOn: $state.notifyOnNewVersion)
                        SettingsDivider()
                        SettingsToggle(title: "New Claude Code version", isOn: $state.notifyOnCLIUpdate)
                        SettingsDivider()
                        SettingsRow(title: "Check for versions every") {
                            PaperSegments(selection: checkIntervalBinding, options: IntervalOption.updateCheck, label: "Check interval")
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button("Send test notification", action: sendTestNotification)
                        .buttonStyle(.paper)
                    if testSent {
                        Text("Sent")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
            .opacity(state.notificationsEnabled ? 1 : 0.5)
            .disabled(!state.notificationsEnabled)
        }
    }

    private var permissionRow: some View {
        SettingsRow(title: "System permission", subtitle: permissionStatus) {
            if permissionDenied {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.paper)
            }
        }
    }

    private var thresholdNote: String? {
        state.criticalThreshold <= state.warningThreshold ? "Critical has to be higher than warning." : nil
    }

    private func thresholdRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, tint: Color) -> some View {
        SettingsRow(title: title) {
            HStack(spacing: 10) {
                Slider(value: value, in: range, step: 5)
                    .tint(tint)
                    .frame(width: 200)
                    .accessibilityLabel("\(title) threshold")
                    .accessibilityValue(UsageFormat.percent(value.wrappedValue))
                Text(UsageFormat.percent(value.wrappedValue))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .frame(width: 40, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
    }

    private var checkIntervalBinding: Binding<IntervalOption> {
        Binding(
            get: { IntervalOption.matching(state.updateCheckInterval, in: IntervalOption.updateCheck) },
            set: {
                state.updateCheckInterval = $0.seconds
                state.restartUpdateCheckPolling()
            }
        )
    }

    private func checkPermission() {
        Task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            permissionDenied = status == .denied
            permissionStatus = switch status {
            case .authorized: "Allowed"
            case .denied: "Denied. Allow Spark in System Settings > Notifications."
            case .notDetermined: "Not asked yet"
            case .provisional: "Provisional"
            case .ephemeral: "Ephemeral"
            @unknown default: "Unknown"
            }
        }
    }

    private func requestAndCheck() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            checkPermission()
        }
    }

    private func sendTestNotification() {
        Task {
            let granted = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            checkPermission()
            guard granted == true else { return }
            NotificationPoster.post(NoticeWording.test, id: "test-\(UUID())")
            testSent = true
            try? await Task.sleep(for: .seconds(3))
            testSent = false
        }
    }
}
