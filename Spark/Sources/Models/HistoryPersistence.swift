import Foundation

// MARK: - Daily rollup

/// A closed calendar day's token totals and session count, persisted permanently — unlike the
/// snapshot ring buffer, rollups survive both the `maxHistoryEntries` cap and Claude Code's
/// transcript retention window, since once a day has ended its totals never change again.
struct DailyRollup: Codable, Equatable, Sendable {
    var sessionCount: Int
    var input = 0
    var output = 0
    var cacheCreation = 0
    var cacheRead = 0
    /// Total tokens per raw model ID — mirrors `TranscriptCache`'s per-model dimension, kept
    /// deliberately as its own copy rather than reusing `DayAggregate` directly, so history.json's
    /// persistence schema evolves independently of the transcript-scan cache's internal format.
    var modelTotals: [String: Int] = [:]

    var totalTokens: Int { input + output + cacheCreation + cacheRead }

    /// Excludes cache reads — reused context, not fresh consumption. Mirrors
    /// `ModelTokenTotals.real`/`LiveStats.realTokens`, the figure shown as the headline number
    /// everywhere else in the app.
    var real: Int { input + output + cacheCreation }

    /// Builds a rollup dictionary by adding any day in `closedDays` not already present in
    /// `existing`. Closed days are immutable, so an already-recorded day is never touched —
    /// this is what lets rollups survive both `history.json`'s snapshot cap and Claude Code's
    /// transcript retention window without ever needing to be recomputed.
    static func merging(_ closedDays: [String: DayAggregate], into existing: [String: DailyRollup]) -> [String: DailyRollup] {
        var result = existing
        for (day, bucket) in closedDays where result[day] == nil {
            result[day] = DailyRollup(
                sessionCount: bucket.sessionIds.count,
                input: bucket.input,
                output: bucket.output,
                cacheCreation: bucket.cacheCreation,
                cacheRead: bucket.cacheRead,
                modelTotals: bucket.perModel.mapValues { $0.total }
            )
        }
        return result
    }
}

// MARK: - History file

/// The full contents of `history.json`: the snapshot ring buffer plus permanent daily rollups.
struct HistoryFile: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let empty = HistoryFile(schemaVersion: currentSchemaVersion, snapshots: [], rollups: [:])

    var schemaVersion: Int
    var snapshots: [UsageSnapshot]
    var rollups: [String: DailyRollup]
}

// MARK: - Persistence

enum HistoryPersistence {
    /// Loads `history.json`, tolerating the pre-rollup format it shipped in (a bare
    /// `[UsageSnapshot]` array, no wrapper object). A file that can't be read as either format
    /// yields an empty history rather than throwing — existing history is never lost to a
    /// decode error, but it is also never silently fabricated from unreadable bytes.
    static func load(from url: URL) -> HistoryFile {
        guard let data = try? Data(contentsOf: url) else { return .empty }

        if let wrapped = try? JSONDecoder().decode(HistoryFile.self, from: data) {
            return wrapped
        }
        if let legacySnapshots = try? JSONDecoder().decode([UsageSnapshot].self, from: data) {
            return HistoryFile(schemaVersion: HistoryFile.currentSchemaVersion, snapshots: legacySnapshots, rollups: [:])
        }
        return .empty
    }

    static func save(_ file: HistoryFile, to url: URL) {
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: url)
        }
    }
}
