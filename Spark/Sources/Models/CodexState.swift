import Combine
import os
import SwiftUI
import UserNotifications

/// The Codex provider: credentials, polling and notifications. Kept apart from `AppState`, which
/// stays the Claude provider, so a Claude-only user runs exactly the code paths they ran before.
/// Everything here is inert until `auth.json` with a ChatGPT sign-in exists.
@MainActor
final class CodexState: ObservableObject {
    @Published private(set) var usage: CodexUsage?
    @Published private(set) var isAvailable = false
    @Published private(set) var needsSignIn = false
    @Published private(set) var isLoading = false
    /// Every new error clears `isRateLimited`; the rate-limit path sets it again after the message.
    @Published private(set) var lastError: String? { didSet { isRateLimited = false } }
    /// The last error is the API rate limit, which the backoff handles: the data is not stale yet.
    @Published private(set) var isRateLimited = false

    @Published private(set) var stats: CodexSessionStats?

    @AppStorage("codexEnabled") var isEnabled: Bool = true
    /// Separate from Claude's `statsPeriod`: switching one tab's period must not leave the
    /// other tab's numbers computed for a period it no longer shows.
    @AppStorage("codexStatsPeriod") private(set) var statsPeriod: StatsPeriod = .today

    /// Shown in tabs, the menu bar and notifications only when this is true.
    var isActive: Bool { isEnabled && isAvailable }

    private static let log = Logger(subsystem: "com.konradmichalik.spark", category: "codex")
    private static let pollInterval: TimeInterval = 300
    private static let signInRecheckInterval: TimeInterval = 900

    private var pollCancellable: AnyCancellable?
    private var lastFetchTime: Date = .distantPast
    private var consecutiveRateLimits = 0
    private var lastLevels: [String: UsageLevel] = [:]
    private var statsTask: Task<Void, Never>?

    /// Arguments only seed state for tests; the app starts empty and fills in via `onLaunch()`.
    init(usage: CodexUsage? = nil, isAvailable: Bool = false) {
        self.usage = usage
        self.isAvailable = isAvailable
    }

    // MARK: - Lifecycle

    func onLaunch() {
        refreshAvailability()
        guard isActive else { return }
        refreshStats()
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
            usage = nil
            stats = nil
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
        usage = CodexUsage(response: response)
        needsSignIn = false
        lastError = nil
        consecutiveRateLimits = 0
        startPolling(interval: Self.pollInterval)
        refreshStats()
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

    /// Re-reads the rollout files on every usage poll. Unlike Claude there is no transcript cache
    /// yet: the files are only scanned past the cutoff and only matching lines are decoded. A new
    /// refresh cancels the previous scan, so a slow "All" scan can neither pile up nor finish
    /// last and overwrite newer numbers.
    func refreshStats() {
        let period = statsPeriod
        let directories = [CodexHome.sessionsDirectory, CodexHome.current.appendingPathComponent("archived_sessions")]
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

    // MARK: - Notifications

    /// Threshold notifications per Codex window, using the same thresholds as Claude.
    func checkAndNotify() {
        guard isActive, let usage else { return }
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "notificationsEnabled") as? Bool ?? true else { return }
        let warning = defaults.object(forKey: "warningThreshold") as? Double ?? 75
        let critical = defaults.object(forKey: "criticalThreshold") as? Double ?? 90

        for (label, utilization) in Self.windows(of: usage) {
            let level: UsageLevel = utilization >= critical ? .critical : utilization >= warning ? .warning : .ok
            defer { lastLevels[label] = level }
            guard level != .ok, level != lastLevels[label, default: .ok] else { continue }
            Self.sendNotification(
                id: "codex-usage-\(label)-\(level.rawValue)",
                title: "Codex \(label) usage at \(Int(utilization))%",
                body: "Codex \(label) limit \(level == .critical ? "almost reached" : "approaching"). "
                    + "\(100 - Int(utilization))% remaining."
            )
        }
    }

    private static func windows(of usage: CodexUsage) -> [(String, Double)] {
        var result: [(String, Double)] = []
        if let session = usage.usageData.session { result.append(("Session", session.utilization)) }
        if let weekly = usage.usageData.weekly { result.append(("Weekly", weekly.utilization)) }
        result += usage.additionalLimits.map { ($0.label, $0.bucket.utilization) }
        return result
    }

    nonisolated private static func sendNotification(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
