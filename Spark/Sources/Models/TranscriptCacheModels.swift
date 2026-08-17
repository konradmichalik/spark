import Foundation

// MARK: - Daily aggregate

/// Token totals for one model on one day. Keyed by the raw model ID (e.g. `claude-opus-4-6`) —
/// normalisation and family grouping (see `ModelFamily`) happen only at the display layer, so a
/// new model release doesn't invalidate the cache.
struct ModelTokenTotals: Codable, Equatable, Sendable {
    var input = 0
    var output = 0
    var cacheCreation = 0
    var cacheRead = 0

    var total: Int { input + output + cacheCreation + cacheRead }

    mutating func merge(_ other: ModelTokenTotals) {
        input += other.input
        output += other.output
        cacheCreation += other.cacheCreation
        cacheRead += other.cacheRead
    }
}

/// Token totals for one project on one day, keyed by the encoded project directory name (e.g.
/// `-Users-me-app`) rather than any decoded/display form — two projects whose decoded names would
/// collide stay distinct because the encoded directory name never collides with itself.
struct ProjectTokenTotals: Codable, Equatable, Sendable {
    var input = 0
    var output = 0
    var cacheCreation = 0
    var cacheRead = 0

    var total: Int { input + output + cacheCreation + cacheRead }

    mutating func merge(_ other: ProjectTokenTotals) {
        input += other.input
        output += other.output
        cacheCreation += other.cacheCreation
        cacheRead += other.cacheRead
    }
}

/// Token totals, distinct session IDs, and a per-model breakdown seen on one local calendar day,
/// keyed as `"yyyy-MM-dd"` so it serializes directly as a JSON object key. Carries no project
/// dimension of its own — a day bucket lives inside one file's `FileParseCache`, and a file always
/// belongs to exactly one project (unlike a model, which can vary line to line), so `aggregate()`
/// attributes a whole file's day buckets to that file's project directly rather than needing a
/// per-line dictionary.
struct DayAggregate: Codable, Equatable, Sendable {
    var sessionIds: Set<String> = []
    var input = 0
    var output = 0
    var cacheCreation = 0
    var cacheRead = 0
    var perModel: [String: ModelTokenTotals] = [:]

    mutating func merge(_ other: DayAggregate) {
        sessionIds.formUnion(other.sessionIds)
        input += other.input
        output += other.output
        cacheCreation += other.cacheCreation
        cacheRead += other.cacheRead
        for (model, totals) in other.perModel {
            perModel[model, default: ModelTokenTotals()].merge(totals)
        }
    }
}

// MARK: - Per-file cache entry

/// What's persisted for one transcript file: enough to detect whether it changed since the
/// last scan, and where to resume parsing if it only grew (transcripts are append-only).
struct FileParseCache: Codable, Equatable, Sendable {
    var mtime: Date
    var size: Int64
    var parsedByteOffset: Int64
    var dailyBuckets: [String: DayAggregate]
    /// The first `cwd` seen anywhere in this file, if any — the authoritative source for a
    /// project's readable name. Persisted per file (not re-derived every scan) since it never
    /// changes once found, and an unchanged file is never reopened to look for it again.
    var discoveredCwd: String?
}

// MARK: - Aggregated totals

/// Result of aggregating cached daily buckets over a period. `modelTotals` is keyed by raw model
/// ID — see `DayAggregate.perModel`. `projectTotals` is keyed by the encoded project directory
/// name — see `TranscriptCache.projectKey(forTranscriptAt:projectsDir:)`. `projectDisplayNames`
/// maps that same key to its resolved `cwd`, where one was ever found.
struct TranscriptTotals: Equatable, Sendable {
    var sessionIds: Set<String> = []
    var input = 0
    var output = 0
    var cacheCreation = 0
    var cacheRead = 0
    var modelTotals: [String: ModelTokenTotals] = [:]
    var projectTotals: [String: ProjectTokenTotals] = [:]
    var projectDisplayNames: [String: String] = [:]
}

// MARK: - Store

struct TranscriptCacheStore: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let empty = TranscriptCacheStore(schemaVersion: currentSchemaVersion, files: [:])

    var schemaVersion: Int
    var files: [String: FileParseCache]
}
