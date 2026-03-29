import Foundation
import Combine

@MainActor
class StatusService: ObservableObject {
    @Published var status: ClaudeServiceStatus = .unknown
    @Published var statusDescription: String = "Checking..."
    @Published var claudeCodeStatus: ClaudeServiceStatus = .unknown
    @Published var apiStatus: ClaudeServiceStatus = .unknown
    @Published var components: [(name: String, status: ClaudeServiceStatus)] = []

    private var timer: Timer?

    init() {
        Task { await fetchStatus() }
        startAutoRefresh()
    }

    func fetchStatus() async {
        do {
            let url = URL(string: "https://status.claude.com/api/v2/summary.json")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(StatusPageResponse.self, from: data)

            status = ClaudeServiceStatus(rawValue: response.status.indicator) ?? .unknown
            statusDescription = response.status.description

            if let comps = response.components {
                components = comps.map { (name: $0.name, status: ClaudeServiceStatus(rawValue: $0.status) ?? .unknown) }
                for (name, compStatus) in components {
                    let nameLower = name.lowercased()
                    if nameLower.contains("api") {
                        apiStatus = compStatus
                    }
                    if nameLower.contains("claude.ai") || nameLower.contains("claude code") {
                        claudeCodeStatus = compStatus
                    }
                }
            }

            if claudeCodeStatus == .unknown {
                claudeCodeStatus = status
            }
            if apiStatus == .unknown {
                apiStatus = status
            }
        } catch {
            status = .unknown
            statusDescription = "Status unavailable"
        }
    }

    private func startAutoRefresh() {
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchStatus()
            }
        }
    }
}
