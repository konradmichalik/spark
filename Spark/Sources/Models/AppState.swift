import AppKit
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
    @Published var rollups: [String: DailyRollup] = [:]
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var isAuthenticated = false
    @Published var needsReconnect = false
    @Published var authMethod: AuthMethod = .none
    @Published var accountTier: AccountTier = .free
    @Published var currentRefreshInterval: TimeInterval = 300
    @Published var latestCLIVersion: String?
    @Published var localCLIVersion: String?
    @Published var claudeCodeInstallMethod: ClaudeCodeInstallMethod = .other

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
    @AppStorage("showOpusUsage") var showOpusUsage: Bool = true
    @AppStorage("showFableUsage") var showFableUsage: Bool = true
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
    @AppStorage("updateCheckInterval") var updateCheckInterval: Double = 21600
    @AppStorage("showStats") var showStats: Bool = true
    @AppStorage("showProjectBreakdown") var showProjectBreakdown: Bool = true
    @AppStorage("coloredIcon") var coloredIcon: Bool = true
    @AppStorage("usageDisplayStyle") var usageDisplayStyle: String = "bars"
    @AppStorage("reduceTransparency") var reduceTransparency: Bool = false

    // Navigation
    @Published var selectedSettingsTab: SettingsTab = .general

    // MARK: - Stats

    @Published var liveStats: LiveStats?
    @AppStorage("statsPeriod") private(set) var statsPeriod: StatsPeriod = .today
    @Published var isLoadingStats: Bool = false
    @Published private(set) var weeklyReport: PeriodReport?
    @Published private(set) var isLoadingWeeklyReport: Bool = false
    @Published private(set) var reportPeriod: ReportPeriod = .week
    /// 0 = the current period; 1 = one period back, etc. `WeeklyReportView` resets this to 0 on
    /// every appearance (via `loadWeeklyReport(offset: 0)`), so reopening the window never
    /// strands the user on a past period they navigated to earlier.
    @Published private(set) var reportOffset = 0

    // MARK: - OAuth Token (Keychain)

    private static let log = Logger(subsystem: "com.konradmichalik.spark", category: "auth")
    private var oauthToken: String?

    // MARK: - Private State

    private var usageTimerCancellable: AnyCancellable?
    private var statusTimerCancellable: AnyCancellable?
    private var updateCheckCancellable: AnyCancellable?
    private var reconnectReminderCancellable: AnyCancellable?
    private var lastFetchTime: Date = .distantPast
    private var previousUtilization: Double = 0
    private var idleTicks: Int = 0
    private var consecutiveRateLimits: Int = 0
    private let maxHistoryEntries = 8640 // ~30 days at 5-min intervals

    private var fileWatcher: TranscriptFileWatcher?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var lastLiveStatsRefresh: Date = .distantPast
    private var pendingLiveStatsRefreshTimer: Timer?
    private static let liveStatsMinInterval: TimeInterval = 12

    // Notification tracking
    private var lastSessionLevel: UsageLevel = .ok
    private var lastWeeklyLevel: UsageLevel = .ok
    private var lastStatusNotification: ClaudeServiceStatus = .operational
    private var hasSentSessionResetNotification = true
    private var hasSentWeeklyResetNotification = true
    @AppStorage("lastNotifiedCLIVersion") private var lastNotifiedCLIVersion: String = ""
    @AppStorage("claudeCodeInstallMethod") private var storedInstallMethodRaw: String = ClaudeCodeInstallMethod.other.rawValue

    // MARK: - Lifecycle

    func onLaunch() {
        claudeCodeInstallMethod = ClaudeCodeInstallMethod(rawValue: storedInstallMethodRaw) ?? .other
        loadHistory()
        loadStats()
        tryAutoLogin()
        startStatusPolling()
        startUpdateCheckPolling()
        startFileWatching()
        startSleepWakeObservers()
        if notificationsEnabled {
            requestNotificationPermission()
        }
    }

    // MARK: - Authentication

    func setAuthenticated(token: String) {
        oauthToken = token
        authMethod = .claudeCode
        isAuthenticated = true
        KeychainService.saveOAuthToken(token)
        Task { await fetchUsage() }
    }

    func logout() {
        oauthToken = nil
        isAuthenticated = false
        needsReconnect = false
        authMethod = .none
        accountTier = .free
        usageData = .empty
        KeychainService.clearForLogout()
        stopUsagePolling()
        stopReconnectReminder()
    }

    /// Store a long-lived token (from `claude setup-token`) and switch auth mode.
    /// Bypasses the Claude Code keychain entirely — no macOS password prompts.
    func setLongLivedToken(_ token: String) -> Bool {
        guard let cleaned = KeychainService.cleanedLongLivedToken(token) else {
            Self.log.error("setLongLivedToken: rejected (invalid format)")
            return false
        }
        Self.log.notice("setLongLivedToken: storing long-lived token")
        KeychainService.saveLongLivedToken(cleaned)
        oauthToken = cleaned
        authMethod = .longLivedToken
        isAuthenticated = true
        needsReconnect = false
        stopReconnectReminder()
        Task { await fetchUsage() }
        return true
    }

    /// Remove the long-lived token and fall back to Claude Code keychain on next launch.
    func clearLongLivedToken() {
        Self.log.notice("clearLongLivedToken: removing long-lived token")
        KeychainService.deleteLongLivedToken()
        if authMethod == .longLivedToken {
            logout()
        }
    }

    func loadCredentials() -> Bool {
        Self.log.notice("loadCredentials: reading Claude Code keychain (prompted)")
        guard let credentials = KeychainService.readClaudeCodeCredentials() else {
            Self.log.error("loadCredentials: no credentials found")
            return false
        }
        accountTier = credentials.accountTier
        KeychainService.cacheCredentials(credentials)
        needsReconnect = false
        stopReconnectReminder()
        setAuthenticated(token: credentials.accessToken)
        Self.log.notice("loadCredentials: authenticated (tier: \(credentials.accountTier.displayName, privacy: .public))")
        return true
    }

    /// Re-read Claude Code credentials (prompted). Call from UI when user taps "Reconnect".
    func reconnect() {
        Self.log.notice("reconnect: user-initiated reconnect")
        _ = loadCredentials()
    }

    private func tryAutoLogin() {
        Self.log.notice("tryAutoLogin: starting")

        // Migrate legacy per-field keychain entries into the single consolidated entry
        // and rebind its ACL to the current build — caps password prompts at one and
        // keeps later launches silent. Must run before any other keychain read below.
        KeychainService.migrateAndRebindStore()

        // Long-lived token wins — bypasses Claude Code keychain entirely
        if let longLived = KeychainService.readLongLivedToken(), !longLived.isEmpty {
            Self.log.notice("tryAutoLogin: long-lived token found, using it")
            oauthToken = longLived
            authMethod = .longLivedToken
            isAuthenticated = true
            if let tierName = KeychainService.readCachedTierName() {
                accountTier = AccountTier(displayName: tierName)
            }
            Task { await fetchUsage() }
            return
        }

        // Try saved token first (our own Keychain entry — no password prompt)
        if let token = KeychainService.readCachedOAuthToken(), !token.isEmpty {
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
                weeklyOpus: response.sevenDayOpus,
                weeklyFable: response.sevenDayFable,
                extraUsage: response.extraUsage,
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
        Self.log.notice("refreshTokenAndFetch: attempting silent token refresh")

        // Strategy 1: Use cached refresh token (no Keychain prompt — Spark owns this entry)
        if let cached = KeychainService.readCachedRefreshToken() {
            do {
                let new = try await Task.detached {
                    try await UsageClient.refreshAccessToken(refreshToken: cached.token)
                }.value
                Self.log.notice("refreshTokenAndFetch: OAuth refresh succeeded")
                oauthToken = new.accessToken
                KeychainService.saveRefreshedTokens(new)
                try await fetchUsageAndApply(token: new.accessToken)
                return
            } catch {
                Self.log.error("refreshTokenAndFetch: OAuth refresh failed — \(error.localizedDescription, privacy: .public)")
                // fall through to Strategy 2
            }
        } else {
            Self.log.info("refreshTokenAndFetch: no cached refresh token, falling back to silent Keychain read")
        }

        // Strategy 2: Silent re-read from Claude Code Keychain (may fail if ACL was reset)
        guard let credentials = await Task.detached(operation: {
            KeychainService.readClaudeCodeCredentials(silent: true)
        }).value else {
            Self.log.error("refreshTokenAndFetch: silent read failed — no credentials")
            throw UsageClient.ClientError.unauthorized
        }
        let tokenChanged = credentials.accessToken != oauthToken
        Self.log.notice("refreshTokenAndFetch: token \(tokenChanged ? "changed" : "unchanged", privacy: .public)")
        oauthToken = credentials.accessToken
        accountTier = credentials.accountTier
        KeychainService.cacheCredentials(credentials)
        try await fetchUsageAndApply(token: credentials.accessToken)
    }

    private func fetchUsageAndApply(token: String) async throws {
        let response = try await Task.detached {
            try await UsageClient.fetchUsage(token: token)
        }.value
        usageData = UsageData(
            session: response.fiveHour,
            weekly: response.sevenDay,
            weeklySonnet: response.sevenDaySonnet,
            weeklyOpus: response.sevenDayOpus,
            weeklyFable: response.sevenDayFable,
            extraUsage: response.extraUsage,
            lastUpdated: Date()
        )
        consecutiveRateLimits = 0
        Self.log.notice("refreshTokenAndFetch: fetch succeeded after refresh")
        scheduleNextRefresh()
    }

    private func handleRateLimited() async {
        consecutiveRateLimits += 1
        Self.log.notice("handleRateLimited: attempt \(self.consecutiveRateLimits, privacy: .public)")

        // Try refreshing the token — a new token resets the per-token rate limit.
        do {
            try await refreshTokenAndFetch()
            return
        } catch {
            Self.log.error("handleRateLimited: refresh failed — \(error.localizedDescription, privacy: .public)")
        }

        // Exponential backoff: 10min → 20min → 40min → 60min (cap)
        let backoff = min(600 * pow(2.0, Double(consecutiveRateLimits - 1)), 3600)
        let backoffMinutes = Int(backoff / 60)
        Self.log.notice("handleRateLimited: backing off \(backoffMinutes, privacy: .public) min")
        lastError = "Rate limited. Retrying in \(backoffMinutes) min."
        startUsagePolling(interval: backoff)
    }

    private func handleUnauthorized() async {
        Self.log.notice("handleUnauthorized: 401 received, attempting silent refresh")
        do {
            try await refreshTokenAndFetch()
            Self.log.notice("handleUnauthorized: refresh succeeded")
        } catch {
            // Silent read failed (ACL wiped by Claude Code token rotation).
            // Show reconnect prompt instead of a vague error.
            Self.log.error("handleUnauthorized: refresh failed — triggering needsReconnect")
            needsReconnect = true
            lastError = nil
            stopUsagePolling()
            if notificationsEnabled {
                sendReconnectNotification(id: "reconnect")
            }
            startReconnectReminder()
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

    // MARK: - File Watching

    /// Watches `~/.claude/projects` so Smart Refresh reacts to actual activity instead of only
    /// inferring it from whether the last poll's utilization changed. Missing or unreadable
    /// roots (e.g. no `.claude` directory yet, or a network volume that's unmounted) simply mean
    /// no watcher starts — never a crash — and the app falls back to plain polling.
    private func startFileWatching() {
        let projectsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("projects")
        guard FileManager.default.fileExists(atPath: projectsDir.path) else { return }

        fileWatcher = TranscriptFileWatcher(paths: [projectsDir.path]) { [weak self] in
            Task { @MainActor in
                self?.handleTranscriptFileChange()
            }
        }
    }

    private func stopFileWatching() {
        fileWatcher?.stop()
        fileWatcher = nil
    }

    /// A transcript write means the user is active right now. Throttles the local stats refresh
    /// (see `throttledRefreshLiveStats`) and, if Smart Refresh had backed off to an idle tier,
    /// snaps the API poll back to the active interval instead of waiting for the next scheduled
    /// poll to notice a changed percentage. The existing 60-second debounce in `fetchUsage()`
    /// already bounds how often filesystem activity can translate into API calls, so a burst of
    /// writes can't turn into request spam.
    private func handleTranscriptFileChange() {
        throttledRefreshLiveStats()

        guard refreshMode == "smart", currentRefreshInterval > 300 else { return }
        idleTicks = 0
        currentRefreshInterval = 300
        startUsagePolling(interval: 300)
    }

    /// FSEvents streams don't survive a suspend/resume cycle cleanly, so the watcher is torn
    /// down before sleep and a fresh one re-armed on wake — this also naturally re-resolves which
    /// roots currently exist, picking up a root that appeared or dropping one that vanished while
    /// asleep (e.g. a network volume).
    private func startSleepWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.stopFileWatching()
            }
        }
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.startFileWatching()
            }
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
        updateCheckCancellable = Timer.publish(every: updateCheckInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task {
                    await self.checkForNewVersion()
                    await self.checkForCLIUpdate()
                }
            }
    }

    func restartUpdateCheckPolling() {
        updateCheckCancellable?.cancel()
        startUpdateCheckPolling()
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
            let method = await CLIVersionClient.detectInstallMethod()
            claudeCodeInstallMethod = method
            storedInstallMethodRaw = method.rawValue

            async let remoteResult = Task.detached {
                try await CLIVersionClient.fetchLatestVersion(for: method)
            }.value
            async let localResult = CLIVersionClient.readLocalVersion()

            let local = await localResult
            localCLIVersion = local

            let remote = try await remoteResult
            latestCLIVersion = remote

            guard notificationsEnabled, notifyOnCLIUpdate else { return }
            guard let local, CLIVersionClient.isNewer(remote, than: local) else { return }
            guard lastNotifiedCLIVersion != remote else { return }

            lastNotifiedCLIVersion = remote
            sendNotification(
                id: "cli-update-\(remote)",
                title: "Claude Code \(remote) available",
                body: "You're running \(local). Run `\(method.updateCommand)` to update."
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

    // MARK: - Reconnect Reminder

    /// Start an hourly reminder timer that re-sends the reconnect notification
    /// while `needsReconnect` remains true. Idempotent — no-ops if already running.
    private func startReconnectReminder() {
        guard reconnectReminderCancellable == nil else { return }
        Self.log.notice("startReconnectReminder: starting hourly reminder")
        reconnectReminderCancellable = Timer.publish(every: 3600, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.needsReconnect, self.notificationsEnabled else { return }
                let id = "reconnect-reminder-\(UInt64(Date().timeIntervalSince1970))"
                self.sendReconnectNotification(id: id)
            }
    }

    /// Stop the reconnect reminder timer (called when the user successfully reconnects or logs out).
    private func stopReconnectReminder() {
        guard reconnectReminderCancellable != nil else { return }
        Self.log.notice("stopReconnectReminder: stopping reminder")
        reconnectReminderCancellable?.cancel()
        reconnectReminderCancellable = nil
    }

    nonisolated private func sendReconnectNotification(id: String) {
        sendNotification(
            id: id,
            title: "Spark disconnected",
            body: "Keychain access lost. Open Spark and tap Reconnect to re-authenticate."
        )
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
            weeklyUtilization: usageData.weeklyUtilization,
            sonnetUtilization: usageData.weeklySonnet?.utilization,
            opusUtilization: usageData.weeklyOpus?.utilization,
            fableUtilization: usageData.weeklyFable?.utilization,
            extraUsageSpend: usageData.extraUsage?.spendAmount
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
        let file = HistoryFile(schemaVersion: HistoryFile.currentSchemaVersion, snapshots: history, rollups: rollups)
        HistoryPersistence.save(file, to: historyFileURL)
    }

    private func loadHistory() {
        let file = HistoryPersistence.load(from: historyFileURL)
        history = file.snapshots
        rollups = file.rollups
    }

    /// Folds newly-closed days from the transcript cache into the permanent rollup store.
    private func updateRollups() async {
        let closedDays = await LiveTranscriptCache.shared.closedDayRollups()
        let updated = DailyRollup.merging(closedDays, into: rollups)

        guard updated.count != rollups.count else { return }
        rollups = updated
        saveHistory()
    }

    /// Rollups as pretty-printed JSON, for the Settings export action.
    func exportRollupsJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(rollups)
    }

    /// Clears all permanent rollups. Does not affect the snapshot ring buffer.
    func clearRollups() {
        rollups = [:]
        saveHistory()
    }

    // MARK: - Stats

    func loadStats() {
        refreshLiveStats()
    }

    func setStatsPeriod(_ period: StatsPeriod) {
        guard period != statsPeriod else { return }
        statsPeriod = period
        refreshLiveStats()
    }

    /// Coalesces bursts of filesystem activity so the Stats card updates at most once every
    /// `liveStatsMinInterval` seconds, instead of on every single transcript write — Claude Code
    /// can write several times a second while actively streaming, and `refreshLiveStats` dimming
    /// the Stats card on every one of those reads as flicker rather than as data changing. A
    /// trigger that arrives mid-cooldown still lands: it schedules exactly one trailing refresh
    /// for when the cooldown ends, rather than being dropped.
    private func throttledRefreshLiveStats() {
        let elapsed = Date().timeIntervalSince(lastLiveStatsRefresh)
        guard elapsed < Self.liveStatsMinInterval else {
            lastLiveStatsRefresh = Date()
            refreshLiveStats()
            return
        }

        guard pendingLiveStatsRefreshTimer == nil else { return }
        pendingLiveStatsRefreshTimer = Timer.scheduledTimer(
            withTimeInterval: Self.liveStatsMinInterval - elapsed,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.pendingLiveStatsRefreshTimer = nil
                self.lastLiveStatsRefresh = Date()
                self.refreshLiveStats()
            }
        }
    }

    func refreshLiveStats() {
        let period = statsPeriod
        isLoadingStats = true
        Task.detached {
            let stats = await LiveStatsParser.parseStats(period: period)
            await MainActor.run {
                // Discard results from a stale request if the period changed while parsing ran.
                guard period == self.statsPeriod else { return }
                self.liveStats = stats
                self.isLoadingStats = false
            }
            // Runs after parseStats has warmed the transcript cache for this launch, so this
            // never triggers its own scan.
            await self.updateRollups()
        }
    }

    /// Loaded lazily when the Weekly Report window opens, not on every launch. Pass `period`
    /// and/or `offset` to navigate; omitting both reloads whatever's currently shown, e.g. after
    /// a rollup update. Switching `period` always resets to offset 0 — a week offset carried
    /// over into month mode (or vice versa) would land on an unrelated, confusing window.
    func loadWeeklyReport(period: ReportPeriod? = nil, offset: Int? = nil) {
        guard !isLoadingWeeklyReport else { return }
        if let period, period != reportPeriod {
            reportPeriod = period
            reportOffset = 0
        }
        if let offset { reportOffset = max(0, offset) }
        isLoadingWeeklyReport = true
        let now = Date()
        let shownPeriod = reportPeriod
        let shownOffset = reportOffset
        // Computed from `rollups` before `updateRollups()` below can add to it. Safe: the only
        // way that call changes `windowStart`/`windowEnd` is by adding today's rollup, and
        // `updateRollups` only ever adds *closed* days (never today) — so this snapshot and the
        // one `build` reads after the update always agree on which day the window ends.
        let cutoff = PeriodReport.windowStart(period: shownPeriod, periodOffset: shownOffset, rollups: rollups, now: now)
        let upperCutoff = PeriodReport.windowEnd(period: shownPeriod, periodOffset: shownOffset, rollups: rollups, now: now)
        let statsPeriodLabel: StatsPeriod = shownPeriod == .month ? .month : .week
        Task.detached {
            let stats = await LiveStatsParser.parseStats(period: statsPeriodLabel, cutoffOverride: cutoff, upperCutoff: upperCutoff)
            let topProjects = stats?.topProjects(limit: 5) ?? []
            let modelTotals = stats?.modelTotals ?? [:]
            // Warms the rollup store with any newly-closed day the scan above just discovered,
            // the same way `refreshLiveStats` does — otherwise a report built right after launch
            // (or right after midnight) can be missing yesterday's rollup.
            await self.updateRollups()
            await MainActor.run {
                self.weeklyReport = PeriodReport.build(
                    rollups: self.rollups,
                    modelTotals: modelTotals,
                    topProjects: topProjects,
                    period: shownPeriod,
                    periodOffset: shownOffset,
                    now: now
                )
                self.isLoadingWeeklyReport = false
            }
        }
    }

    var canGoToEarlierPeriod: Bool {
        PeriodReport.hasEarlierPeriod(period: reportPeriod, periodOffset: reportOffset, rollups: rollups)
    }

    var canGoToLaterPeriod: Bool {
        reportOffset > 0
    }

    func goToEarlierPeriod() {
        guard canGoToEarlierPeriod else { return }
        loadWeeklyReport(offset: reportOffset + 1)
    }

    func goToLaterPeriod() {
        guard canGoToLaterPeriod else { return }
        loadWeeklyReport(offset: reportOffset - 1)
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

    // MARK: - Debug

    #if DEBUG
    /// Manually flip into the reconnect state to verify icon + notification behaviour.
    /// Wired to a hidden right-click affordance during development only.
    func debugTriggerReconnect() {
        Self.log.notice("debugTriggerReconnect: forcing needsReconnect = true")
        needsReconnect = true
        if notificationsEnabled {
            sendReconnectNotification(id: "reconnect")
        }
        startReconnectReminder()
    }
    #endif
}

// MARK: - Auth Method

enum AuthMethod: String, Sendable {
    case none
    case claudeCode = "Claude Code"
    case oauth = "OAuth (Browser)"
    case longLivedToken = "Long-lived Token"
}
