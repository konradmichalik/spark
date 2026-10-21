import Combine
import os
import SwiftUI

/// The Codex provider: credentials, polling and notifications. Kept apart from `AppState`, which
/// stays the Claude provider, so a Claude-only user runs exactly the code paths they ran before.
/// Everything here is inert until `auth.json` with a ChatGPT sign-in exists.
@MainActor
final class CodexState: ObservableObject {
    @Published private(set) var usage: CodexUsage?
    @Published private(set) var history: [UsageSnapshot] = []
    @Published private(set) var isAvailable = false
    @Published private(set) var needsSignIn = false
    @Published private(set) var isLoading = false
    /// Every new error clears `isRateLimited`; the rate-limit path sets it again after the message.
    @Published private(set) var lastError: String? { didSet { isRateLimited = false } }
    /// The last error is the API rate limit, which the backoff handles: the data is not stale yet.
    @Published private(set) var isRateLimited = false

    @Published private(set) var stats: CodexSessionStats?
    @Published private(set) var burnRate: BurnRate?
    @Published private(set) var volumeTokensByDay: [String: Int]?
    @Published private(set) var isLoadingVolumeHistory = false

    @AppStorage("codexEnabled") var isEnabled: Bool = true
    /// Separate from Claude's `statsPeriod`: switching one tab's period must not leave the
    /// other tab's numbers computed for a period it no longer shows.
    @AppStorage("codexStatsPeriod") private(set) var statsPeriod: StatsPeriod = .today

    /// Shown in tabs, the menu bar and notifications only when this is true.
    var isActive: Bool { isEnabled && isAvailable }

    private static let log = Logger(subsystem: "com.konradmichalik.spark", category: "codex")
    private static let pollInterval: TimeInterval = 300
    private static let signInRecheckInterval: TimeInterval = 900
    private static let volumeRefreshInterval: TimeInterval = 300

    private var pollCancellable: AnyCancellable?
    private var lastFetchTime: Date = .distantPast
    private var consecutiveRateLimits = 0
    private var levelTracker = UsageLevelTracker()
    private var statsTask: Task<Void, Never>?
    private var lastStatsRefresh: Date?
    private var burnRateTask: Task<Void, Never>?
    private var lastBurnRateRefresh: Date?
    private var burnRateRefreshID = UUID()
    private var volumeTask: Task<Void, Never>?
    private var lastVolumeRefresh: Date?
    private var volumeRefreshID = UUID()
    private var reportDataTask: Task<CodexReportData, Never>?
    private let historyURL: URL?

    /// Arguments only seed state for tests; the app starts empty and fills in via `onLaunch()`.
    init(usage: CodexUsage? = nil, isAvailable: Bool = false, historyURL: URL? = nil) {
        self.usage = usage
        self.isAvailable = isAvailable
        self.historyURL = historyURL
        if let historyURL { history = CodexHistory.load(from: historyURL) }
    }

    // MARK: - Lifecycle

    func onLaunch() {
        history = CodexHistory.load(from: resolvedHistoryURL)
        refreshAvailability()
        guard isActive else { return }
        refreshStats(trigger: .poll)
        Task { await fetchUsage() }
    }

    /// Called when the Settings toggle changes or the user signed in with `codex login`.
    func applySettingsChange() {
        refreshAvailability()
        if isActive {
            Task { await fetchUsage(force: true) }
        } else {
            stopPolling()
            statsTask?.cancel()
            burnRateTask?.cancel()
            volumeTask?.cancel()
            burnRateRefreshID = UUID()
            volumeRefreshID = UUID()
            lastBurnRateRefresh = nil
            lastVolumeRefresh = nil
            usage = nil
            stats = nil
            burnRate = nil
            volumeTokensByDay = nil
            isLoadingVolumeHistory = false
            lastError = nil
            needsSignIn = false
        }
    }

    private func refreshAvailability() {
        isAvailable = CodexAuthReader.read() != nil
    }

    // MARK: - Polling

    func fetchUsage(force: Bool = false) async {
        guard isEnabled else { return }
        if !force, Date().timeIntervalSince(lastFetchTime) < 60 { return }
        guard let credentials = CodexAuthReader.read() else {
            isAvailable = false
            usage = nil
            stopPolling()
            return
        }
        isAvailable = true
        lastFetchTime = Date()
        isLoading = true
        defer { isLoading = false }

        do {
            try await fetchAndApply(credentials)
        } catch UsageClient.ClientError.unauthorized {
            await handleUnauthorized(staleToken: credentials.accessToken)
        } catch UsageClient.ClientError.rateLimited {
            handleRateLimited()
        } catch {
            Self.log.error("fetchUsage failed: \(error.localizedDescription, privacy: .public)")
            lastError = "Codex: \(error.localizedDescription)"
            // A launch before the network is up must not leave Codex without a timer.
            if pollCancellable == nil { startPolling(interval: Self.pollInterval) }
        }
    }

    private func fetchAndApply(_ credentials: CodexCredentials) async throws {
        let response = try await Task.detached {
            try await CodexUsageClient.fetchUsage(credentials: credentials)
        }.value
        // Codex may have been switched off while the request was in flight.
        guard isEnabled else { return }
        applyUsage(CodexUsage(response: response))
        needsSignIn = false
        lastError = nil
        consecutiveRateLimits = 0
        startPolling(interval: Self.pollInterval)
        refreshStats(trigger: .poll)
    }

    /// Apply only successful responses, including a successful retry after a CLI token rotation.
    func applyUsage(_ newUsage: CodexUsage) {
        guard isEnabled else { return }
        usage = newUsage
        let recorded = CodexHistory.recording(newUsage, in: history, at: newUsage.usageData.lastUpdated)
        guard recorded.last?.id != history.last?.id else { return }
        history = recorded
        CodexHistory.save(history, to: resolvedHistoryURL)
    }

    private var resolvedHistoryURL: URL {
        historyURL ?? AppSupportDirectory.spark.appendingPathComponent("codex-history.json")
    }

    /// The CLI refreshes its own token and rewrites `auth.json`. A 401 usually means Spark read
    /// the file just before that happened, so one re-read and retry is tried before asking the
    /// user to sign in again. Spark never refreshes the token itself (see `CodexAuthReader`).
    private func handleUnauthorized(staleToken: String) async {
        if let fresh = CodexAuthReader.read(), fresh.accessToken != staleToken {
            do {
                try await fetchAndApply(fresh)
                return
            } catch {
                Self.log.error("retry after re-read failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        Self.log.notice("Codex token rejected, asking for sign-in")
        needsSignIn = true
        lastError = nil
        // Each poll re-reads auth.json, so a slow poll notices a `codex login` on its own.
        startPolling(interval: Self.signInRecheckInterval)
    }

    private func handleRateLimited() {
        consecutiveRateLimits += 1
        let backoff = min(600 * pow(2.0, Double(consecutiveRateLimits - 1)), 3600)
        lastError = "Codex rate limited. Retrying in \(Int(backoff / 60)) min."
        isRateLimited = true
        startPolling(interval: backoff)
    }

    private func startPolling(interval: TimeInterval) {
        stopPolling()
        pollCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.fetchUsage() }
            }
    }

    private func stopPolling() {
        pollCancellable?.cancel()
        pollCancellable = nil
    }

    // MARK: - Local Stats

    func setStatsPeriod(_ period: StatsPeriod) {
        guard period != statsPeriod else { return }
        statsPeriod = period
        refreshStats()
    }

    /// Called when the Statistics screen opens: the only refresh "All" gets besides picking it.
    func refreshStatsOnVisit() {
        refreshStats(trigger: .visit)
    }

    /// Re-reads the rollout files, on the usage poll for bounded periods (see `CodexStatsRefresh`),
    /// on a visit, or when the period changes. Unlike Claude there is no transcript cache
    /// yet: the files are only scanned past the cutoff and only matching lines are decoded. A new
    /// refresh cancels the previous scan, so a slow "All" scan can neither pile up nor finish
    /// last and overwrite newer numbers.
    func refreshStats(trigger: CodexStatsRefresh.Trigger? = nil) {
        let period = statsPeriod
        if let trigger {
            guard CodexStatsRefresh.shouldRefresh(period: period, trigger: trigger, lastRefresh: lastStatsRefresh, now: Date()) else { return }
        }
        lastStatsRefresh = Date()
        let directories = rolloutDirectories
        statsTask?.cancel()
        statsTask = Task.detached {
            let stats = CodexSessionStats.parse(directories: directories, since: period.startDate)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard period == self.statsPeriod else { return }
                self.stats = stats
            }
        }
    }

    /// Recent local token activity is deliberately scanned independently from the statistics
    /// period, and only while the overview that shows it is visible.
    func refreshBurnRate() {
        guard isActive else { return }
        let now = Date()
        guard CodexBurnRateRefresh.shouldRefresh(lastRefresh: lastBurnRateRefresh, now: now) else { return }
        lastBurnRateRefresh = now
        let refreshID = UUID()
        burnRateRefreshID = refreshID
        let cutoff = now.addingTimeInterval(-BurnRate.window)
        let directories = rolloutDirectories
        burnRateTask?.cancel()
        burnRateTask = Task.detached {
            let samples = CodexTurnSamples.parse(directories: directories, cutoff: cutoff, now: now)
            guard !Task.isCancelled else { return }
            let rate = BurnRate.calculate(turns: samples, now: now)
            await MainActor.run {
                guard CodexBurnRateRefresh.canPublish(
                    scanID: refreshID, currentScanID: self.burnRateRefreshID, isActive: self.isActive
                ) else { return }
                self.burnRate = rate
            }
        }
    }

    private var rolloutDirectories: [URL] {
        [CodexHome.sessionsDirectory, CodexHome.current.appendingPathComponent("archived_sessions")]
    }

    func refreshVolumeHistory() {
        guard isActive else { return }
        let now = Date()
        guard lastVolumeRefresh.map({ now.timeIntervalSince($0) >= Self.volumeRefreshInterval }) ?? true else { return }
        lastVolumeRefresh = now
        let refreshID = UUID()
        volumeRefreshID = refreshID
        isLoadingVolumeHistory = true
        let cutoff = Calendar.current.date(byAdding: .day, value: -31, to: now) ?? now.addingTimeInterval(-31 * 86_400)
        let directories = rolloutDirectories
        volumeTask?.cancel()
        volumeTask = Task.detached {
            let totals = CodexSessionStats.parse(directories: directories, since: cutoff).dayTokens
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.isActive, self.volumeRefreshID == refreshID else { return }
                self.volumeTokensByDay = totals
                self.isLoadingVolumeHistory = false
            }
        }
    }

    func earliestActivityDay() async -> String? {
        let directories = rolloutDirectories
        return await Task.detached { CodexEarliestDay.dayKey(in: directories) }.value
    }

    /// What the usage report needs from Codex: fresh tokens per day from `previousStart` on (for the
    /// calendar and the trend), plus per model and project for the shown period. A separate scan from
    /// `refreshStats`, off the main actor, and a newer request cancels the previous one.
    func reportData(previousStart: Date, start: Date, until: Date?) async -> CodexReportData {
        let directories = rolloutDirectories
        reportDataTask?.cancel()
        let task = Task.detached {
            let days = CodexSessionStats.parse(directories: directories, since: previousStart, until: until).dayTokens
            let stats = CodexSessionStats.parse(directories: directories, since: start, until: until)
            return CodexReportData(dayTokens: days, modelTokens: stats.modelTokens, projectTokens: stats.projectTokens)
        }
        reportDataTask = task
        return await task.value
    }

    // MARK: - Notifications

    /// Threshold notifications per Codex window, using the same thresholds as Claude.
    func checkAndNotify() {
        guard isActive, let usage else { return }
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "notificationsEnabled") as? Bool ?? true else { return }
        let warning = defaults.object(forKey: "warningThreshold") as? Double ?? 75
        let critical = defaults.object(forKey: "criticalThreshold") as? Double ?? 90

        let windows = Self.windows(of: usage)
        let crossings = levelTracker.update(windows.map { ($0.key, $0.bucket.utilization) }, warning: warning, critical: critical)
        for crossing in crossings {
            guard let window = windows.first(where: { $0.key == crossing.key }) else { continue }
            let notice = NoticeWording.usage(
                provider: .codex, window: window.label, value: crossing.utilization,
                tone: UsageTone(value: crossing.utilization, warning: warning, critical: critical),
                resetsAt: window.bucket.resetsAtDate, limitIn: nil
            )
            NotificationPoster.post(notice, id: "codex-usage-\(crossing.key)-\(crossing.level.rawValue)")
        }
    }

    private struct NotifiedWindow {
        let key: String
        let label: String
        let bucket: UsageBucket
    }

    /// `key` is unique per window, unlike the label, which can repeat among the additional limits.
    private static func windows(of usage: CodexUsage) -> [NotifiedWindow] {
        var result: [NotifiedWindow] = []
        if let session = usage.usageData.session { result.append(NotifiedWindow(key: "session", label: "Session", bucket: session)) }
        if let weekly = usage.usageData.weekly { result.append(NotifiedWindow(key: "week", label: "Week", bucket: weekly)) }
        result += usage.additionalLimits.map { NotifiedWindow(key: $0.id, label: $0.label, bucket: $0.bucket) }
        return result
    }
}
