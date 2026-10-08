import SwiftUI

/// The settings window: one tab per area, each on paper with cards (boards 10 and 10b).
struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TabView(selection: $state.selectedSettingsTab) {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            MenuBarTab()
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
                .tag(SettingsTab.menuBar)

            DisplayTab()
                .tabItem { Label("Display", systemImage: "square.grid.2x2") }
                .tag(SettingsTab.display)

            ConnectionsTab()
                .tabItem { Label("Connections", systemImage: "link") }
                .tag(SettingsTab.connection)

            NotificationsTab()
                .tabItem { Label("Notifications", systemImage: "bell") }
                .tag(SettingsTab.notifications)

            StatusTab()
                .tabItem { Label("Status", systemImage: "waveform.path.ecg") }
                .tag(SettingsTab.status)

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 540, height: 560)
        .background(Theme.paper)
        .onAppear {
            NSApp.activate()
        }
    }
}

// MARK: - Preview thumbnails

/// The bars style in small: a Doto value over the session and week dot bars.
struct BarsPreviewThumb: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("45").font(.doto(size: 18))
                Text("%").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(Theme.ink)
            DotBar(value: 45, pitch: 4, dotSize: 2.6)
                .frame(height: 5)
            DotBar(value: 30, pitch: 4, dotSize: 2.2)
                .frame(height: 4)
        }
        .frame(width: 56)
        .accessibilityHidden(true)
    }
}

struct RingThumb: View {
    var body: some View {
        DotRing(value: 72, projected: 85, count: 20, gap: 1, dotSize: 3)
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)
    }
}

struct GlyphThumb: View {
    let logo: MenuBarLogo?

    var body: some View {
        Image(nsImage: MenuBarGlyph(value: 45, tone: .normal).image(logo: logo))
            .renderingMode(.template)
            .foregroundStyle(Theme.ink)
            .scaleEffect(1.5)
            .accessibilityHidden(true)
    }
}
