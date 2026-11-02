import Foundation

extension CodexState {
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

    /// The user's own median and 90th percentile over 14 days of rollout files, rebuilt every six
    /// hours while the overview is visible.
    func refreshBurnRateBaseline() {
        guard isActive else { return }
        let now = Date()
        let interval = CodexBurnRateRefresh.baselineInterval
        guard CodexBurnRateRefresh.shouldRefresh(lastRefresh: lastBaselineRefresh, now: now, interval: interval) else { return }
        lastBaselineRefresh = now
        let refreshID = UUID()
        baselineRefreshID = refreshID
        let cutoff = now.addingTimeInterval(-BurnRateBaseline.span)
        let directories = rolloutDirectories
        baselineTask?.cancel()
        baselineTask = Task.detached {
            let samples = CodexTurnSamples.parse(directories: directories, cutoff: cutoff, now: now)
            guard !Task.isCancelled else { return }
            let baseline = BurnRateBaseline.calculate(windowTokens: BurnRateBaseline.windowTokens(of: samples), now: now)
            await MainActor.run {
                guard CodexBurnRateRefresh.canPublish(
                    scanID: refreshID, currentScanID: self.baselineRefreshID, isActive: self.isActive
                ) else { return }
                self.burnRateBaseline = baseline
            }
        }
    }
}
