import SwiftUI
import Combine
import UserNotifications

// swiftlint:disable file_length

@MainActor
// swiftlint:disable:next type_body_length
final class AppState: ObservableObject {

    // MARK: - Published State

    @Published var usageData: UsageData = .empty
    @Published var history: [UsageSnapshot] = []
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var isAuthenticated = false
    @Published var authMethod: AuthMethod = .none
    @Published var accountTier: AccountTier = .free
    @Published var currentRefreshInterval: TimeInterval = 300

    // Status
    @Published var status: ClaudeServiceStatus = .unknown
    @Published var statusDescription: String = "Checking..."
    @Published var claudeCodeStatus: ClaudeServiceStatus = .unknown
    @Published var apiStatus: ClaudeServiceStatus = .unknown
    @Published var components: [(name: String, status: ClaudeServiceStatus)] = []

    // MARK: - Settings (persisted)

    @AppStorage("iconStyle") var iconStyle: String = "logo"
    @AppStorage("menuBarValue") var menuBarValue: String = "max"
    @AppStorage("showSonnetUsage") var showSonnetUsage: Bool = true
    @AppStorage("showGraph") var showGraph: Bool = true
    @AppStorage("showProjection") var showProjection: Bool = true
    @AppStorage("refreshMode") var refreshMode: String = "smart"
    @AppStorage("refreshInterval") var refreshInterval: Double = 300
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = true
    @AppStorage("warningThreshold") var warningThreshold: Double = 75
    @AppStorage("criticalThreshold") var criticalThreshold: Double = 90
    @AppStorage("notifyOnReset") var notifyOnReset: Bool = true
    @AppStorage("notifyOnStatusChange") var notifyOnStatusChange: Bool = true
    @AppStorage("showStats") var showStats: Bool = true
    @AppStorage("coloredIcon") var coloredIcon: Bool = true

    // MARK: - Stats

    @Published var liveStats: LiveDayStats?

    // MARK: - OAuth Token (Keychain)

    private var oauthToken: String?

    // MARK: - Private State

    private var usageTimerCancellable: AnyCancellable?
    private var statusTimerCancellable: AnyCancellable?
    private var lastFetchTime: Date = .distantPast
    private var previousUtilization: Double = 0
    private var idleTicks: Int = 0
    private let maxHistoryEntries = 8640 // ~30 days at 5-min intervals

    // Notification tracking
    private var lastSessionLevel: UsageLevel = .ok
    private var lastWeeklyLevel: UsageLevel = .ok
    private var lastStatusNotification: ClaudeServiceStatus = .operational
    private var hasSentSessionResetNotification = true
    private var hasSentWeeklyResetNotification = true

    // MARK: - Lifecycle

    func onLaunch() {
        loadHistory()
        loadStats()
        tryAutoLogin()
        startStatusPolling()
        if notificationsEnabled {
            requestNotificationPermission()
        }
    }

    // MARK: - Authentication

    func setAuthenticated(token: String) {
        oauthToken = token
        authMethod = .claudeCode
        isAuthenticated = true
        KeychainService.save(token, account: "oauth-token")
        Task { await fetchUsage() }
    }

    func logout() {
        oauthToken = nil
        isAuthenticated = false
        authMethod = .none
        usageData = .empty
        KeychainService.delete(account: "oauth-token")
        stopUsagePolling()
    }

    func loadCredentials() -> Bool {
        if let credentials = KeychainService.readClaudeCodeCredentials() {
            accountTier = credentials.accountTier
            setAuthenticated(token: credentials.accessToken)
            return true
        }
        return false
    }

    private func tryAutoLogin() {
        // Always read credentials to get tier info
        if let credentials = KeychainService.readClaudeCodeCredentials() {
            accountTier = credentials.accountTier
        }

        // Try saved token first
        if let token = KeychainService.read(account: "oauth-token"), !token.isEmpty {
            oauthToken = token
            authMethod = .claudeCode
            isAuthenticated = true
            Task { await fetchUsage() }
            return
        }

        // Try Claude Code Keychain
        _ = loadCredentials()
    }

    // MARK: - Usage Polling

    // swiftlint:disable:next function_body_length
    func fetchUsage() async {
        guard let token = oauthToken else { return }

        // Debounce: minimum 30 seconds between requests
        let elapsed = Date().timeIntervalSince(lastFetchTime)
        if elapsed < 30 { return }
        lastFetchTime = Date()

        isLoading = true
        lastError = nil

        do {
            let response = try await Task.detached {
                try await UsageClient.fetchUsage(token: token)
            }.value

            usageData = UsageData(
                session: response.fiveHour,
                weekly: response.sevenDay,
                weeklySonnet: response.sevenDaySonnet,
                lastUpdated: Date()
            )
            addHistorySnapshot()
            refreshLiveStats()
            scheduleNextRefresh()
        } catch let error as UsageClient.ClientError {
            switch error {
            case .rateLimited:
                lastError = "Rate limited. Retrying in 10 minutes."
                startUsagePolling(interval: 600)
            case .unauthorized:
                if let newToken = KeychainService.readClaudeCodeToken() {
                    oauthToken = newToken
                    KeychainService.save(newToken, account: "oauth-token")
                    do {
                        let response = try await Task.detached {
                            try await UsageClient.fetchUsage(token: newToken)
                        }.value
                        usageData = UsageData(
                            session: response.fiveHour,
                            weekly: response.sevenDay,
                            weeklySonnet: response.sevenDaySonnet,
                            lastUpdated: Date()
                        )
                    } catch {
                        lastError = error.localizedDescription
                    }
                } else {
                    lastError = error.localizedDescription
                }
            default:
                lastError = error.localizedDescription
            }
        } catch {
            lastError = error.localizedDescription
        }

        isLoading = false
    }

    private func scheduleNextRefresh() {
        if refreshMode == "smart" {
            let newUtilization = usageData.maxUtilization
            let changed = abs(newUtilization - previousUtilization) >= 1.0
            previousUtilization = newUtilization

            if changed {
                idleTicks = 0
                currentRefreshInterval = 300
            } else {
                idleTicks += 1
                switch idleTicks {
                case 0...2: currentRefreshInterval = 300
                case 3...5: currentRefreshInterval = 600
                case 6...10: currentRefreshInterval = 900
                default: currentRefreshInterval = 1800
                }
            }
            startUsagePolling(interval: currentRefreshInterval)
        } else {
            currentRefreshInterval = refreshInterval
            startUsagePolling(interval: refreshInterval)
        }
    }

    func startUsagePolling(interval: TimeInterval = 300) {
        stopUsagePolling()
        usageTimerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.fetchUsage() }
            }
    }

    func stopUsagePolling() {
        usageTimerCancellable?.cancel()
        usageTimerCancellable = nil
    }

    // MARK: - Status Polling

    func fetchStatus() async {
        do {
            let response = try await Task.detached {
                try await UsageClient.fetchStatus()
            }.value

            status = ClaudeServiceStatus(rawValue: response.status.indicator) ?? .unknown
            statusDescription = response.status.description

            if let comps = response.components {
                components = comps.map { (name: $0.name, status: ClaudeServiceStatus(rawValue: $0.status) ?? .unknown) }
                let knownAPINames = ["api", "anthropic api"]
                let knownCodeNames = ["claude.ai", "claude code", "claude for work"]
                for (name, compStatus) in components {
                    let nameLower = name.lowercased()
                    if knownAPINames.contains(where: { nameLower.contains($0) }) {
                        apiStatus = compStatus
                    }
                    if knownCodeNames.contains(where: { nameLower.contains($0) }) {
                        claudeCodeStatus = compStatus
                    }
                }
            }

            if claudeCodeStatus == .unknown { claudeCodeStatus = status }
            if apiStatus == .unknown { apiStatus = status }
        } catch {
            status = .unknown
            statusDescription = "Status unavailable"
        }
    }

    private func startStatusPolling() {
        Task { await fetchStatus() }
        statusTimerCancellable = Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.fetchStatus() }
            }
    }

    // MARK: - Notifications

    func requestNotificationPermission() {
        Task {
            try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    func checkAndNotify() {
        guard notificationsEnabled else { return }

        checkUsageNotification(
            label: "Session",
            utilization: usageData.sessionUtilization,
            lastLevel: &lastSessionLevel
        )
        checkUsageNotification(
            label: "Weekly",
            utilization: usageData.weeklyUtilization,
            lastLevel: &lastWeeklyLevel
        )
        checkStatusNotification()
        checkResetNotification()
    }

    private func checkUsageNotification(label: String, utilization: Double, lastLevel: inout UsageLevel) {
        let newLevel = levelFor(utilization)
        if newLevel != lastLevel && newLevel != .ok {
            let title = "\(label) usage at \(Int(utilization))%"
            let body: String
            switch newLevel {
            case .warning:
                body = "Claude Code \(label) limit approaching. \(100 - Int(utilization))% remaining."
            case .critical:
                body = "Claude Code \(label) limit almost reached! Only \(100 - Int(utilization))% remaining."
            case .ok:
                lastLevel = newLevel
                return
            }
            sendNotification(id: "usage-\(label)-\(newLevel.rawValue)", title: title, body: body)
        }
        lastLevel = newLevel
    }

    private func checkStatusNotification() {
        if notifyOnStatusChange && status != lastStatusNotification && !status.isHealthy {
            sendNotification(
                id: "status-\(status.rawValue)",
                title: "Claude Status: \(status.displayName)",
                body: "Claude Code is currently experiencing issues."
            )
        }
        lastStatusNotification = status
    }

    private func checkResetNotification() {
        guard notifyOnReset else { return }

        // Reset the "sent" flags once utilization climbs back above 10%
        if usageData.sessionUtilization >= 10 { hasSentSessionResetNotification = false }
        if usageData.weeklyUtilization >= 10 { hasSentWeeklyResetNotification = false }

        if usageData.sessionUtilization < 5, !hasSentSessionResetNotification {
            sendNotification(id: "reset-session", title: "Session limit reset", body: "Your Claude Code session usage has been reset.")
            hasSentSessionResetNotification = true
        }

        if usageData.weeklyUtilization < 5, !hasSentWeeklyResetNotification {
            sendNotification(id: "reset-weekly", title: "Weekly limit reset", body: "Your Claude Code weekly usage has been reset.")
            hasSentWeeklyResetNotification = true
        }
    }

    private func levelFor(_ utilization: Double) -> UsageLevel {
        if utilization >= criticalThreshold { return .critical }
        if utilization >= warningThreshold { return .warning }
        return .ok
    }

    nonisolated private func sendNotification(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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
        // swiftlint:disable:next force_unwrapping
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Spark")
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

    // MARK: - Stats

    func loadStats() {
        refreshLiveStats()
    }

    func refreshLiveStats() {
        Task.detached {
            let stats = LiveStatsParser.parseTodayStats()
            await MainActor.run { self.liveStats = stats }
        }
    }

    // MARK: - CLI Helpers

    func openCLILogin() {
        let script = """
        tell application "Terminal"
            activate
            do script "claude auth login"
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var errorInfo: NSDictionary?
            appleScript.executeAndReturnError(&errorInfo)
        }
    }
}

// MARK: - Auth Method

enum AuthMethod: String, Sendable {
    case none
    case claudeCode = "Claude Code"
    case oauth = "OAuth (Browser)"
}
