import SwiftUI
import UniformTypeIdentifiers

/// The wording of the About tab's data section: plain words for what is stored, not the
/// internal term "rollup".
enum AboutText {
    static let dailyTotalsNote =
        "Spark keeps one token total per day for Claude Code, so reports reach back past the days Claude Code keeps its transcripts."
    static let exportTitle = "Export daily totals\u{2026}"
    static let clearTitle = "Clear daily totals"
}

struct AboutTab: View {
    @EnvironmentObject var state: AppState
    @State private var updateState: UpdateCheckState = .idle
    @State private var showClearRollupsConfirmation = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            SparkMark(size: 80, style: .tile)
            Text("spark")
                .font(.doto(size: 34, weight: 800))
                .foregroundStyle(Theme.ink)
            secondary("Version \(appVersion)")
            Text("AI coding usage in your menu bar.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSecondary)
            HStack(spacing: 8) {
                Link(destination: URL(staticString: "https://konradmichalik.github.io/spark/")) {
                    TablerLabel("Website", icon: .world, tint: Theme.ink)
                }
                Link(destination: URL(staticString: "https://github.com/konradmichalik/spark")) {
                    TablerLabel("GitHub", icon: .link, tint: Theme.ink)
                }
            }
            .buttonStyle(.paper)
            updateCheckSection
            rollupDataSection
            Spacer()
            credits
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Theme.paper)
    }

    private func secondary(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.inkSecondary)
    }

    private var credits: some View {
        VStack(spacing: 3) {
            secondary("\u{00A9} 2026 Konrad Michalik")
            Link("Icons by Tabler Icons (MIT)", destination: URL(staticString: "https://tabler.io/icons"))
            Link("Doto font by The Doto Project Authors (OFL)", destination: URL(staticString: "https://fonts.google.com/specimen/Doto"))
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.inkSecondary)
        .tint(Theme.inkSecondary)
    }

    private var rollupDataSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button(AboutText.exportTitle) { exportRollups() }
                Button(AboutText.clearTitle) { showClearRollupsConfirmation = true }
            }
            .buttonStyle(.paper)
            .disabled(state.rollups.isEmpty)
            Text(AboutText.dailyTotalsNote)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)
        }
        .confirmationDialog("Clear all daily totals?", isPresented: $showClearRollupsConfirmation) {
            Button(AboutText.clearTitle, role: .destructive) { state.clearRollups() }
        } message: {
            Text("This permanently deletes the daily token totals Spark recorded beyond the transcript retention window. This cannot be undone.")
        }
    }

    private func exportRollups() {
        guard let data = state.exportRollupsJSON() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "spark-rollups.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }

    @ViewBuilder
    private var updateCheckSection: some View {
        switch updateState {
        case .idle:
            Button("Check for updates") {
                Task { await checkForUpdates() }
            }
            .buttonStyle(.paper)
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .upToDate:
            TablerLabel("You're up to date", icon: .circleCheck, tint: Theme.ink)
                .foregroundStyle(Theme.ink)
        case .available(let version, let url):
            HStack(spacing: 8) {
                TablerLabel("Version \(version) is available", icon: .circleArrowUp, tint: Theme.ink)
                    .foregroundStyle(Theme.ink)
                Link("Download", destination: url)
                    .buttonStyle(.paperPrimary)
            }
        case .error(let message):
            TablerLabel(message, icon: .alertTriangle, tint: Theme.warning)
                .foregroundStyle(Theme.ink)
        }
    }

    private func checkForUpdates() async {
        updateState = .checking
        let url = URL(staticString: "https://api.github.com/repos/konradmichalik/spark/releases/latest")
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            if latestVersion == appVersion {
                updateState = .upToDate
            } else if let releaseURL = URL(string: release.htmlUrl) {
                updateState = .available(version: latestVersion, url: releaseURL)
            } else {
                updateState = .error("Could not read the release link")
            }
        } catch {
            updateState = .error("Could not check for updates")
        }
    }
}

private enum UpdateCheckState {
    case idle
    case checking
    case upToDate
    case available(version: String, url: URL)
    case error(String)
}

struct GitHubRelease: Decodable {
    let tagName: String
    let htmlUrl: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
    }
}
