import SwiftUI

struct NotConnectedView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header — matches MenuBarView
            HStack(spacing: 6) {
                SparkMark(size: 18)
                Text("spark")
                    .font(.doto(size: 19, weight: 800))
                Spacer()
                SettingsLink {
                    TablerIconView(.settings, size: 12, isDecorative: false)
                }
                .buttonStyle(.borderless)
                .tooltip("Settings")
                .accessibilityLabel("Settings")
            }

            // The connected popover keeps exactly one divider because section cards carry its
            // grouping; this view has no sections and no cards, so its two dividers remain the
            // only structural separation between header, content, and footer. The two states are
            // mutually exclusive on screen, so the inconsistency is invisible in practice.
            Divider()

            // Connection status card
            VStack(spacing: 10) {
                TablerIconView(.linkPlus, size: 24, color: Theme.sparkOrange)

                Text("Not connected")
                    .font(.caption)
                    .foregroundColor(.secondary)

                SettingsLink {
                    HStack(spacing: 4) {
                        TablerIconView(.externalLink, size: 10)
                        Text("Connect")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            // Error
            if let error = state.lastError {
                WarningBanner(message: error)
            }

            Divider()

            // Footer — matches MenuBarView
            HStack {
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    TablerIconView(.power, size: 12, isDecorative: false)
                }
                .buttonStyle(.borderless)
                .tooltip("Quit")
                .accessibilityLabel("Quit")
            }
        }
        .padding(14)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.paper)
        .background(WindowResizer())
        .onAppear {
            state.selectedSettingsTab = .connection
        }
    }
}
