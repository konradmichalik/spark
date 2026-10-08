import Foundation

// MARK: - Transcript lines

extension TranscriptCache {
    struct SessionEntry: Decodable {
        let message: SessionMessage?
        let timestamp: String?
        let sessionId: String?
        let requestId: String?
        let cwd: String?
    }

    struct SessionMessage: Decodable {
        let id: String?
        let role: String?
        let model: String?
        let usage: TokenUsage?
    }

    struct TokenUsage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheCreationTokens: Int?
        let cacheReadTokens: Int?
        /// Missing in older transcripts, whose cache writes then count as 5-minute writes.
        let cacheCreation: CacheCreationBreakdown?
        // swiftlint:disable:next nesting
        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationTokens = "cache_creation_input_tokens"
            case cacheReadTokens = "cache_read_input_tokens"
            case cacheCreation = "cache_creation"
        }
    }

    struct CacheCreationBreakdown: Decodable {
        let oneHourTokens: Int?
        // swiftlint:disable:next nesting
        enum CodingKeys: String, CodingKey {
            case oneHourTokens = "ephemeral_1h_input_tokens"
        }
    }
}

// MARK: - Daily aggregate

/// Token totals for one model on one day. Keyed by the raw model ID (e.g. `claude-opus-4-6`) —
/// normalisation and family grouping (see `ModelFamily`) happen only at the display layer, so a
/// new model release doesn't invalidate the cache.
struct ModelTokenTotals: Codable, Equatable, Sendable {
    var input = 0
    var output = 0
    var cacheCreation = 0
    var cacheRead = 0
    /// The part of `cacheCreation` written to the 1-hour cache, which is billed at a higher rate.
    var cacheCreation1h = 0

    var total: Int { input + output + cacheCreation + cacheRead }

    /// Excludes cache reads — reused context, not fresh consumption — so this reflects what was
    /// actually newly processed rather than the full (mostly cached) API throughput.
    var real: Int { input + output + cacheCreation }

    mutating func merge(_ other: ModelTokenTotals) {
        input += other.input
        output += other.output
        cacheCreation += other.cacheCreation
        cacheRead += other.cacheRead
        cacheCreation1h += other.cacheCreation1h
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

    /// Excludes cache reads — see `ModelTokenTotals.real`.
    var real: Int { input + output + cacheCreation }

    mutating func merge(_ other: ProjectTokenTotals) {
        input += other.input
        output += other.output
        cacheCreation += other.cacheCreation
        cacheRead += other.cacheRead
    }
}

/// Token totals, distinct session IDs, and a per-model breakdown seen on one local calendar day,
/// keyed as `"yyyy-MM-dd"` so it serializes directly as a JSON object key. Carries no project
/// dimension of its own — a day bucket lives inside one file's `FileParseCache`, and a file
/// always belongs to exactly one project (unlike a model, which can vary line to line), so
/// `aggregate()` attributes a whole file's day buckets to that file's project directly rather
/// than needing a per-line dictionary.
struct DayAggregate: Codable, Equatable, Sendable {
    var sessionIds: Set<String> = []
    var input = 0
    var output = 0
    var cacheCreation = 0
    var cacheRead = 0
    var perModel: [String: ModelTokenTotals] = [:]

    /// Excludes cache reads — see `ModelTokenTotals.real`.
    var real: Int { input + output + cacheCreation }

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

/// Identifies one already-counted `(message.id, requestId)` pair, including across two separate
/// incremental scans of the same file. A structured key rather than a colon-joined string, which
/// risks two distinct pairs colliding if either component could itself contain the delimiter.
struct DedupKey: Codable, Equatable, Hashable, Sendable {
    let messageId: String
    let requestId: String
}

/// What's persisted for one transcript file: enough to detect whether it changed since the last
/// scan, where to resume parsing if it only grew (transcripts are append-only), which
/// `(message.id, requestId)` pairs are already counted so a later scan doesn't recount a
/// duplicate written after this file was last parsed, and the project's readable name.
struct FileParseCache: Codable, Equatable, Sendable {
    var mtime: Date
    var size: Int64
    var parsedByteOffset: Int64
    var dailyBuckets: [String: DayAggregate]
    var seenDedupKeys: Set<DedupKey> = []
    /// The first `cwd` seen anywhere in this file, if any — the authoritative source for a
    /// project's readable name. Persisted per file (not re-derived every scan) since it never
    /// changes once found, and an unchanged file is never reopened to look for it again.
    var discoveredCwd: String?
    /// The most recent assistant turn's `input + cache_creation + cache_read` tokens — an
    /// approximation of the conversation's current context-window size, since Claude Code resends
    /// the full context on every turn. Unlike `discoveredCwd` this is a "last seen wins" value,
    /// not "first seen wins": it's overwritten by every newer usage-bearing line, carrying
    /// forward unchanged across an incremental scan that finds no new one.
    var lastContextTokens: Int?
    /// Counted turns of the last `BurnRate.window`, the input for `BurnRate.calculate`.
    var recentTurns: [TurnSample] = []
    /// The earliest and latest timestamp of any line in this file.
    var activity: ActivitySpan?
}

/// The first and last moment something was written, for a file or a whole session.
struct ActivitySpan: Codable, Equatable, Sendable {
    var first: Date
    var last: Date

    var duration: TimeInterval { last.timeIntervalSince(first) }

    func including(_ other: ActivitySpan?) -> ActivitySpan {
        guard let other else { return self }
        return ActivitySpan(first: min(first, other.first), last: max(last, other.last))
    }
}

/// One session's share of a period, its subagent transcripts included. Tokens are clipped to the
/// period by day like `projectTotals`; `activity` spans the whole session, but only of the files
/// with a day inside the period, so a root file entirely outside it adds no span.
struct SessionTotals: Equatable, Sendable {
    let projectKey: String
    var real = 0
    var modelTotals: [String: ModelTokenTotals] = [:]
    var activity: ActivitySpan?
}

// MARK: - Aggregated totals

/// Result of aggregating cached daily buckets over a period. `modelTotals` is keyed by raw model
/// ID — see `DayAggregate.perModel`. `projectTotals` is keyed by the encoded project directory
/// name, and `projectDisplayNames` maps that same key to its resolved `cwd`, where one was found.
struct TranscriptTotals: Equatable, Sendable {
    var sessionIds: Set<String> = []
    /// Day keys with fresh tokens in the period. Idle days are left out so averages per day
    /// describe the days the user actually worked.
    var activeDays: Set<String> = []
    var input = 0
    var output = 0
    var cacheCreation = 0
    var cacheRead = 0
    var modelTotals: [String: ModelTokenTotals] = [:]
    var projectTotals: [String: ProjectTokenTotals] = [:]
    /// Per project, then per raw model ID. Only the cost estimate needs it, since a price
    /// belongs to a model, not to a project.
    var projectModelTotals: [String: [String: ModelTokenTotals]] = [:]
    var projectDisplayNames: [String: String] = [:]
    /// Keyed by session ID. Only sessions with a day inside the period.
    var sessionTotals: [String: SessionTotals] = [:]

    mutating func addSession(_ sessionId: String, project: String, bucket: DayAggregate, activity: ActivitySpan?) {
        var session = sessionTotals[sessionId] ?? SessionTotals(projectKey: project)
        session.real += bucket.real
        for (model, totals) in bucket.perModel {
            session.modelTotals[model, default: ModelTokenTotals()].merge(totals)
        }
        session.activity = activity?.including(session.activity) ?? session.activity
        sessionTotals[sessionId] = session
    }

    mutating func addModels(_ perModel: [String: ModelTokenTotals], project: String?) {
        for (model, totals) in perModel {
            modelTotals[model, default: ModelTokenTotals()].merge(totals)
            if let project {
                projectModelTotals[project, default: [:]][model, default: ModelTokenTotals()].merge(totals)
            }
        }
    }
}

// MARK: - Store

struct TranscriptCacheStore: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 5
    static let empty = TranscriptCacheStore(schemaVersion: currentSchemaVersion, files: [:])

    var schemaVersion: Int
    var files: [String: FileParseCache]
}
