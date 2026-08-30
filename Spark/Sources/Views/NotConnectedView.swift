import SwiftUI

struct NotConnectedView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header — matches MenuBarView
            HStack(spacing: 6) {
                SparkLogoView(size: 20)
                Text("Spark")
                    .font(.custom("InstrumentSerif-Regular", size: 15))
                Spacer()
                SettingsLink {
                    TablerIconView(.settings, size: 12)
                }
                .buttonStyle(.borderless)
                .help("Settings")
            }

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
                HStack {
                    TablerIconView(.alertTriangle, color: .orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Footer — matches MenuBarView
            HStack {
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    TablerIconView(.power, size: 12)
                }
                .buttonStyle(.borderless)
                .help("Quit")
            }
        }
        .padding(12)
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            if state.reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .background(WindowResizer())
        .onAppear {
            state.selectedSettingsTab = .connection
        }
    }
}
