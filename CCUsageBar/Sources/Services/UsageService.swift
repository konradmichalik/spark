import Foundation
import Combine

@MainActor
class UsageService: ObservableObject {
    @Published var usageData: UsageData = .empty
    @Published var isLoading = false
    @Published var error: String?
    @Published var isAuthenticated = false
    @Published var authMethod: AuthMethod = .none
    @Published var history: [UsageSnapshot] = []

    private var timer: Timer?
    private var organizationId: String?
    private var oauthToken: String?
    private let maxHistoryEntries = 288

    // Smart Frequency
    private var previousUtilization: Double = 0
    private var idleTicks: Int = 0 // how many consecutive fetches with no change
    @Published var currentRefreshInterval: TimeInterval = 60

    init() {
        loadHistory()
        // Auto-detect Claude Code credentials on launch
        tryAutoLogin()
    }

    // MARK: - Authentication

    func setAuthenticated(token: String) {
        oauthToken = token
        authMethod = .claudeCode
        isAuthenticated = true
        KeychainHelper.save(key: "cc-usage-bar-token", value: token)
        Task { await fetchUsage() }
    }

    func logout() {
        oauthToken = nil
        isAuthenticated = false
        authMethod = .none
        usageData = .empty
        KeychainHelper.delete(key: "cc-usage-bar-token")
        stopAutoRefresh()
    }

    private func tryAutoLogin() {
        // Try saved token first
        if let token = KeychainHelper.read(key: "cc-usage-bar-token"), !token.isEmpty {
            oauthToken = token
            authMethod = .claudeCode
            isAuthenticated = true
            Task { await fetchUsage() }
            return
        }

        // Try reading from Claude Code Keychain
        Task {
            if let (token, _) = readClaudeCodeCredentials() {
                setAuthenticated(token: token)
            }
        }
    }

    func readClaudeCodeCredentials() -> (String, String?)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else {
            return nil
        }

        return (token, nil)
    }

    // MARK: - Fetch Usage (via api.anthropic.com - no Cloudflare!)

    private var lastFetchTime: Date = .distantPast

    func fetchUsage() async {
        guard let token = oauthToken else { return }

        // Debounce: minimum 30 seconds between requests
        let elapsed = Date().timeIntervalSince(lastFetchTime)
        if elapsed < 30 { return }
        lastFetchTime = Date()

        isLoading = true
        error = nil

        do {
            let usage = try await fetchUsageFromAPI(token: token)
            usageData = UsageData(
                session: usage.fiveHour,
                weekly: usage.sevenDay,
                weeklySonnet: usage.sevenDaySonnet,
                lastUpdated: Date()
            )
            addHistorySnapshot()
            scheduleNextRefresh()
        } catch {
            if let usageError = error as? UsageError {
                switch usageError {
                case .rateLimited:
                    // Silent backoff - don't show error, wait 10 minutes
                    startAutoRefresh(interval: 600)
                case .unauthorized:
                    if let (newToken, _) = readClaudeCodeCredentials() {
                        oauthToken = newToken
                        KeychainHelper.save(key: "cc-usage-bar-token", value: newToken)
                        do {
                            let usage = try await fetchUsageFromAPI(token: newToken)
                            usageData = UsageData(
                                session: usage.fiveHour,
                                weekly: usage.sevenDay,
                                weeklySonnet: usage.sevenDaySonnet,
                                lastUpdated: Date()
                            )
                        } catch {
                            self.error = error.localizedDescription
                        }
                    } else {
                        self.error = error.localizedDescription
                    }
                default:
                    self.error = error.localizedDescription
                }
            } else {
                self.error = error.localizedDescription
            }
        }

        isLoading = false
    }

    private func scheduleNextRefresh() {
        let mode = UserDefaults.standard.string(forKey: "refreshMode") ?? "smart"

        if mode == "smart" {
            let newUtilization = usageData.maxUtilization
            let changed = abs(newUtilization - previousUtilization) >= 1.0
            previousUtilization = newUtilization

            if changed {
                // Active: usage is changing
                idleTicks = 0
                currentRefreshInterval = 300 // 5 min
            } else {
                idleTicks += 1
                // Progressive slowdown: 5min -> 10min -> 15min -> 30min
                switch idleTicks {
                case 0...2: currentRefreshInterval = 300
                case 3...5: currentRefreshInterval = 600
                case 6...10: currentRefreshInterval = 900
                default: currentRefreshInterval = 1800
                }
            }
            startAutoRefresh(interval: currentRefreshInterval)
        } else {
            // Fixed interval from settings
            let interval = UserDefaults.standard.object(forKey: "refreshInterval") as? Double ?? 60
            currentRefreshInterval = interval
            startAutoRefresh(interval: interval)
        }
    }

    private func fetchUsageFromAPI(token: String) async throws -> UsageAPIResponse {
        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw UsageError.networkError
        }

        switch http.statusCode {
        case 200:
            return try JSONDecoder().decode(UsageAPIResponse.self, from: data)
        case 401, 403:
            throw UsageError.unauthorized
        case 429:
            throw UsageError.rateLimited
        default:
            throw UsageError.serverError(http.statusCode)
        }
    }

    // MARK: - Auto Refresh

    func startAutoRefresh(interval: TimeInterval = 60) {
        stopAutoRefresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchUsage()
            }
        }
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - History

    private func addHistorySnapshot() {
        let snapshot = UsageSnapshot(
            sessionUtilization: usageData.sessionUtilization,
            weeklyUtilization: usageData.weeklyUtilization
        )
        history.append(snapshot)
        if history.count > maxHistoryEntries {
            history.removeFirst(history.count - maxHistoryEntries)
        }
        saveHistory()
    }

    private var historyFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("CCUsageBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: historyFileURL)
        }
    }

    private func loadHistory() {
        if let data = try? Data(contentsOf: historyFileURL),
           let loaded = try? JSONDecoder().decode([UsageSnapshot].self, from: data) {
            history = loaded
        }
    }
}

// MARK: - Auth Method

enum AuthMethod: String {
    case none
    case claudeCode = "Claude Code"
    case oauth = "OAuth (Browser)"
}

// MARK: - Errors

enum UsageError: LocalizedError, Equatable {
    case unauthorized
    case noOrganization
    case networkError
    case rateLimited
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Token expired. Refreshing automatically."
        case .noOrganization: return "No organization found."
        case .networkError: return "Network error."
        case .rateLimited: return "Rate limit reached."
        case .serverError(let code): return "Server error: \(code)"
        }
    }
}

// MARK: - Keychain Helper

enum KeychainHelper {
    static func save(key: String, value: String) {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "cc-usage-bar",
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "cc-usage-bar",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "cc-usage-bar",
        ]
        SecItemDelete(query as CFDictionary)
    }
}
