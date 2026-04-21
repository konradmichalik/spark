import Combine
import os
import SwiftUI
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
    @Published var needsReconnect = false
    @Published var authMethod: AuthMethod = .none
    @Published var accountTier: AccountTier = .free
    @Published var currentRefreshInterval: TimeInterval = 300
    @Published var latestCLIVersion: String?
    @Published var localCLIVersion: String?

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
    @AppStorage("notifyOnNewVersion") var notifyOnNewVersion: Bool = true
    @AppStorage("notifyOnCLIUpdate") var notifyOnCLIUpdate: Bool = true
    @AppStorage("showStats") var showStats: Bool = true
    @AppStorage("coloredIcon") var coloredIcon: Bool = true
    @AppStorage("usageDisplayStyle") var usageDisplayStyle: String = "bars"
    @AppStorage("reduceTransparency") var reduceTransparency: Bool = false

    // Navigation
    @Published var selectedSettingsTab: SettingsTab = .general

    // MARK: - Stats

    @Published var liveStats: LiveDayStats?

    // MARK: - OAuth Token (Keychain)

    private static let log = Logger(subsystem: "com.konradmichalik.spark", category: "auth")
    private var oauthToken: String?

    // MARK: - Private State

    private var usageTimerCancellable: AnyCancellable?
    private var statusTimerCancellable: AnyCancellable?
    private var updateCheckCancellable: AnyCancellable?
    private var lastFetchTime: Date = .distantPast
    private var previousUtilization: Double = 0
    private var idleTicks: Int = 0
    private var consecutiveRateLimits: Int = 0
    private let maxHistoryEntries = 8640 // ~30 days at 5-min intervals

    // Notification tracking
    private var lastSessionLevel: UsageLevel = .ok
    private var lastWeeklyLevel: UsageLevel = .ok
    private var lastStatusNotification: ClaudeServiceStatus = .operational
    private var hasSentSessionResetNotification = true
    private var hasSentWeeklyResetNotification = true
    @AppStorage("lastNotifiedCLIVersion") private var lastNotifiedCLIVersion: String = ""

    // MARK: - Lifecycle

    func onLaunch() {
        loadHistory()
        loadStats()
        tryAutoLogin()
        startStatusPolling()
        startUpdateCheckPolling()
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
        needsReconnect = false
        authMethod = .none
        accountTier = .free
        usageData = .empty
        KeychainService.delete(account: "oauth-token")
        KeychainService.delete(account: "account-tier")
        stopUsagePolling()
    }

    func loadCredentials() -> Bool {
        Self.log.info("loadCredentials: reading Claude Code keychain (prompted)")
        guard let credentials = KeychainService.readClaudeCodeCredentials() else {
            Self.log.error("loadCredentials: no credentials found")
            return false
        }
        accountTier = credentials.accountTier
        KeychainService.cacheCredentials(credentials)
        needsReconnect = false
        setAuthenticated(token: credentials.accessToken)
        Self.log.info("loadCredentials: authenticated (tier: \(credentials.accountTier.displayName, privacy: .public))")
        return true
    }

    /// Re-read Claude Code credentials (prompted). Call from UI when user taps "Reconnect".
    func reconnect() {
        Self.log.info("reconnect: user-initiated reconnect")
        _ = loadCredentials()
    }

    private func tryAutoLogin() {
        Self.log.info("tryAutoLogin: starting")

        // Try saved token first (our own Keychain entry — no password prompt)
        if let token = KeychainService.read(account: "oauth-token"), !token.isEmpty {
            Self.log.info("tryAutoLogin: cached token found")
            oauthToken = token
            authMethod = .claudeCode
            isAuthenticated = true

            // Restore cached tier from Spark's own Keychain (no prompt)
            if let tierName = KeychainService.readCachedTierName() {
                accountTier = AccountTier(displayName: tierName)
                Self.log.info("tryAutoLogin: cached tier restored (\(tierName, privacy: .public))")
            } else if let credentials = KeychainService.readClaudeCodeCredentials() {
                // No cached tier yet — read from Claude Code Keychain (may prompt once)
                accountTier = credentials.accountTier
                KeychainService.cacheCredentials(credentials)
                Self.log.info("tryAutoLogin: tier fetched from Claude Code keychain")
            } else {
                Self.log.info("tryAutoLogin: no tier available, using cached token only")
            }

            Task { await fetchUsage() }
            return
        }

        Self.log.info("tryAutoLogin: no cached token, falling back to Claude Code keychain")
        // No saved token — try Claude Code Keychain (single read, may prompt once)
        _ = loadCredentials()
    }

    // MARK: - Usage Polling

    func fetchUsage() async {
        guard let token = oauthToken else { return }

        // Debounce: minimum 60 seconds between requests
        let elapsed = Date().timeIntervalSince(lastFetchTime)
        if elapsed < 60 { return }
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
            consecutiveRateLimits = 0
            addHistorySnapshot()
            refreshLiveStats()
            scheduleNextRefresh()
        } catch let error as UsageClient.ClientError {
            switch error {
            case .rateLimited:
                await handleRateLimited()
            case .unauthorized:
                await handleUnauthorized()
            default:
                lastError = error.localizedDescription
            }
        } catch {
            lastError = error.localizedDescription
        }

        isLoading = false
    }

    private func refreshTokenAndFetch() async throws {
        Self.log.info("refreshTokenAndFetch: attempting silent token refresh")
        guard let credentials = KeychainService.readClaudeCodeCredentials(silent: true) else {
            Self.log.error("refreshTokenAndFetch: silent read failed — no credentials")
            throw UsageClient.ClientError.unauthorized
        }
        let tokenChanged = credentials.accessToken != oauthToken
        Self.log.info("refreshTokenAndFetch: token \(tokenChanged ? "changed" : "unchanged", privacy: .public)")
        oauthToken = credentials.accessToken
        accountTier = credentials.accountTier
        KeychainService.cacheCredentials(credentials)
        let token = credentials.accessToken
        let response = try await Task.detached {
            try await UsageClient.fetchUsage(token: token)
        }.value
        usageData = UsageData(
            session: response.fiveHour,
            weekly: response.sevenDay,
            weeklySonnet: response.sevenDaySonnet,
            lastUpdated: Date()
        )
        consecutiveRateLimits = 0
        Self.log.info("refreshTokenAndFetch: fetch succeeded after refresh")
        scheduleNextRefresh()
    }

    private func handleRateLimited() async {
        consecutiveRateLimits += 1
        Self.log.info("handleRateLimited: attempt \(self.consecutiveRateLimits, privacy: .public)")

        // Try refreshing the token — a new token resets the per-token rate limit.
        if let credentials = KeychainService.readClaudeCodeCredentials(silent: true),
           credentials.accessToken != oauthToken {
            Self.log.info("handleRateLimited: token changed, attempting refresh")
            do {
                try await refreshTokenAndFetch()
                return
            } catch {
                Self.log.error("handleRateLimited: refresh failed — \(error.localizedDescription, privacy: .public)")
            }
        }

        // Exponential backoff: 10min → 20min → 40min → 60min (cap)
        let backoff = min(600 * pow(2.0, Double(consecutiveRateLimits - 1)), 3600)
        let backoffMinutes = Int(backoff / 60)
        Self.log.info("handleRateLimited: backing off \(backoffMinutes, privacy: .public) min")
        lastError = "Rate limited. Retrying in \(backoffMinutes) min."
        startUsagePolling(interval: backoff)
    }

    private func handleUnauthorized() async {
        Self.log.info("handleUnauthorized: 401 received, attempting silent refresh")
        do {
            try await refreshTokenAndFetch()
            Self.log.info("handleUnauthorized: refresh succeeded")
        } catch {
            // Silent read failed (ACL wiped by Claude Code token rotation).
            // Show reconnect prompt instead of a vague error.
            Self.log.error("handleUnauthorized: refresh failed — triggering needsReconnect")
            needsReconnect = true
            lastError = nil
            stopUsagePolling()
        }
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

    // MARK: - Update Check

    private func startUpdateCheckPolling() {
        Task {
            await checkForNewVersion()
            await checkForCLIUpdate()
        }
        // Check every 6 hours
        updateCheckCancellable = Timer.publish(every: 21600, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task {
                    await self.checkForNewVersion()
                    await self.checkForCLIUpdate()
                }
            }
    }

    private func checkForNewVersion() async {
        guard notificationsEnabled, notifyOnNewVersion else { return }

        guard let url = URL(
            string: "https://api.github.com/repos/konradmichalik/spark/releases/latest"
        ) else { return }

        do {
            let (data, _) = try await Task.detached {
                try await URLSession.shared.data(from: url)
            }.value
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

            if CLIVersionClient.isNewer(latest, than: current) {
                sendNotification(
                    id: "update-\(latest)",
                    title: "Spark \(latest) available",
                    body: "A new version of Spark is available. Open Settings → About to update."
                )
            }
        } catch {
            // Silently ignore update check failures
        }
    }

    private func checkForCLIUpdate() async {
        do {
            async let remoteResult = Task.detached {
                try await CLIVersionClient.fetchLatestVersion()
            }.value
            async let localResult = CLIVersionClient.readLocalVersion()

            let remote = try await remoteResult
            let local = await localResult

            latestCLIVersion = remote
            localCLIVersion = local

            guard notificationsEnabled, notifyOnCLIUpdate else { return }
            guard let local, CLIVersionClient.isNewer(remote, than: local) else { return }
            guard lastNotifiedCLIVersion != remote else { return }

            lastNotifiedCLIVersion = remote
            sendNotification(
                id: "cli-update-\(remote)",
                title: "Claude Code \(remote) available",
                body: "You're running \(local). Run `claude update` or `npm update -g @anthropic-ai/claude-code` to update."
            )
        } catch {
            // Silently ignore — non-critical check
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
