import Foundation

/// Codex owns its limit snapshots; Claude's history and daily token rollups are never reused.
enum CodexHistory {
    private static let maxEntries = 8640 // ~30 days at five-minute intervals

    static func load(from url: URL) -> [UsageSnapshot] {
        Array(HistoryPersistence.load(from: url).snapshots.suffix(maxEntries))
    }

    static func save(_ snapshots: [UsageSnapshot], to url: URL) {
        HistoryPersistence.save(
            HistoryFile(schemaVersion: HistoryFile.currentSchemaVersion, snapshots: snapshots, rollups: [:]), to: url
        )
    }

    static func recording(_ usage: CodexUsage, in history: [UsageSnapshot], at now: Date) -> [UsageSnapshot] {
        let session = usage.usageData.session?.utilization
        let weekly = usage.usageData.weekly?.utilization
        guard session != nil || weekly != nil else { return history }
        let snapshot = UsageSnapshot(
            timestamp: now, sessionUtilization: session ?? 0, weeklyUtilization: weekly ?? 0,
            sessionMissing: session == nil, weeklyMissing: weekly == nil
        )
        return Array((history + [snapshot]).suffix(maxEntries))
    }
}
