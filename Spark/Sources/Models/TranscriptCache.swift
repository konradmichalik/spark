import Foundation

// MARK: - Daily aggregate

/// Token totals and distinct session IDs seen on one local calendar day, keyed as `"yyyy-MM-dd"`
/// so it serializes directly as a JSON object key.
struct DayAggregate: Codable, Equatable, Sendable {
    var sessionIds: Set<String> = []
    var input = 0
    var output = 0
    var cacheCreation = 0
    var cacheRead = 0

    mutating func merge(_ other: DayAggregate) {
        sessionIds.formUnion(other.sessionIds)
        input += other.input
        output += other.output
        cacheCreation += other.cacheCreation
        cacheRead += other.cacheRead
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
/// scan, where to resume parsing if it only grew (transcripts are append-only), and which
/// `(message.id, requestId)` pairs are already counted so a later scan doesn't recount a
/// duplicate written after this file was last parsed.
struct FileParseCache: Codable, Equatable, Sendable {
    var mtime: Date
    var size: Int64
    var parsedByteOffset: Int64
    var dailyBuckets: [String: DayAggregate]
    var seenDedupKeys: Set<DedupKey> = []
}

// MARK: - Store

struct TranscriptCacheStore: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2
    static let empty = TranscriptCacheStore(schemaVersion: currentSchemaVersion, files: [:])

    var schemaVersion: Int
    var files: [String: FileParseCache]
}

// MARK: - Cache engine

/// Maintains a per-file, per-day cache of transcript token totals so that:
///
/// - An unchanged file (same mtime + size as cached) is never reopened.
/// - A grown file is parsed only from its previously recorded byte offset onward, since
///   Claude Code transcripts are append-only.
/// - Switching between `Today`/`7d`/`30d`/`All` is pure arithmetic over already-cached daily
///   buckets, with no file I/O — the cache always covers full history regardless of which
///   period the UI currently shows.
///
/// Deliberate deviation from a period-based mtime prefilter: skipping files whose mtime predates
/// the *currently selected* period would leave the cache incomplete for broader periods,
/// violating the "switching periods performs no file I/O" requirement the first time a broader
/// period is selected after a narrower one. Instead every file is always cache-checked (which
/// itself costs no I/O when unchanged), and the period cutoff is applied only when summing
/// already-cached daily buckets.
///
/// Day-bucket granularity means the `7d`/`30d` boundary rounds down to the start of the cutoff's
/// calendar day rather than the exact hour — a disclosed precision tradeoff (widening the window
/// slightly, never narrowing it) in exchange for O(1) period switching.
enum TranscriptCache {
    struct SessionEntry: Decodable {
        let message: SessionMessage?
        let timestamp: String?
        let sessionId: String?
        let requestId: String?
    }

    struct SessionMessage: Decodable {
        let id: String?
        let role: String?
        let usage: TokenUsage?
    }

    struct TokenUsage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheCreationTokens: Int?
        let cacheReadTokens: Int?
        // swiftlint:disable:next nesting
        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationTokens = "cache_creation_input_tokens"
            case cacheReadTokens = "cache_read_input_tokens"
        }
    }

    /// Skips assistant entries that share a `(message.id, requestId)` pair already seen. Claude
    /// Code writes duplicate usage-bearing entries for a single response (one per streamed block,
    /// e.g. text + tool_use), each carrying the identical `usage` payload. Scoped per file, since
    /// every duplicate pair observed in practice shares a single transcript file. Seeded from
    /// `FileParseCache.seenDedupKeys` and read back via `seenKeys`, so a duplicate is still caught
    /// even when its two halves are written on either side of an incremental scan boundary.
    struct TokenDeduplicator {
        private(set) var seenKeys: Set<DedupKey>

        init(seenKeys: Set<DedupKey> = []) {
            self.seenKeys = seenKeys
        }

        /// Entries missing either field are always counted, so an unexpected schema change
        /// doesn't silently drop their tokens instead of merely failing to dedupe them.
        mutating func shouldCount(messageId: String?, requestId: String?) -> Bool {
            guard let messageId, let requestId else { return true }
            return seenKeys.insert(DedupKey(messageId: messageId, requestId: requestId)).inserted
        }
    }

    /// Derives the session a transcript file belongs to, from its path relative to `projects/`.
    /// A session file's stem IS the session ID (`<project>/<uuid>.jsonl`). A subagent file's
    /// stem is an agent identifier, not a session (`<project>/<uuid>/subagents/agent-*.jsonl`) —
    /// its session is the directory two levels up. Returns `nil` for any other shape, so callers
    /// can fall back to the entry's own `sessionId` field.
    static func sessionId(forTranscriptAt url: URL, projectsDir: URL) -> String? {
        let relative = Array(url.pathComponents.dropFirst(projectsDir.pathComponents.count))
        switch relative.count {
        case 2 where relative[1].hasSuffix(".jsonl"):
            return String(relative[1].dropLast(".jsonl".count))
        case 4 where relative[2] == "subagents":
            return relative[1]
        default:
            return nil
        }
    }

    // swiftlint:disable large_tuple
    /// Scans every transcript under `claudeDir/projects`, updating `store` in place, and returns
    /// totals filtered to `cutoff` (`nil` = all-time). Files whose cache entry already matches
    /// their on-disk mtime/size are never opened.
    static func aggregate(
        claudeDir: URL,
        cutoff: Date?,
        store: inout TranscriptCacheStore
    ) -> (sessionIds: Set<String>, input: Int, output: Int, cacheCreation: Int, cacheRead: Int) {
        // swiftlint:enable large_tuple
        // `FileManager.enumerator` fully resolves symlinks in the paths it yields (e.g. macOS's
        // `/var` -> `/private/var`), while `URL.resolvingSymlinksInPath()` deliberately leaves
        // BSD alias roots like `/var` and `/tmp` unresolved. Left unreconciled, the two disagree
        // on path-component count, breaking `sessionId(forTranscriptAt:)`'s depth-based
        // resolution — resolve with `realpath(3)` up front so both sides agree.
        let projectsDir = resolvedPath(claudeDir.appendingPathComponent("projects"))
        guard let enumerator = FileManager.default.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ([], 0, 0, 0, 0)
        }

        let cutoffDayKey = cutoff.map { dayKey(for: $0) }

        var sessionIds: Set<String> = []
        var totalInput = 0
        var totalOutput = 0
        var totalCacheCreation = 0
        var totalCacheRead = 0

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            guard let resourceValues = try? fileURL.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey]
            ),
                let mtime = resourceValues.contentModificationDate,
                let size = resourceValues.fileSize else {
                continue
            }

            let path = fileURL.path
            let updated = updatedCache(
                existing: store.files[path],
                fileURL: fileURL,
                mtime: mtime,
                size: Int64(size),
                pathSessionId: sessionId(forTranscriptAt: fileURL, projectsDir: projectsDir)
            )
            store.files[path] = updated

            for (day, bucket) in updated.dailyBuckets where isWithin(day: day, cutoffDayKey: cutoffDayKey) {
                sessionIds.formUnion(bucket.sessionIds)
                totalInput += bucket.input
                totalOutput += bucket.output
                totalCacheCreation += bucket.cacheCreation
                totalCacheRead += bucket.cacheRead
            }
        }

        return (sessionIds, totalInput, totalOutput, totalCacheCreation, totalCacheRead)
    }

    /// Fully resolves symlinks via `realpath(3)`, unlike `URL.resolvingSymlinksInPath()` which
    /// intentionally preserves BSD alias roots (`/var`, `/tmp`, `/etc`). Falls back to the
    /// original URL if the path doesn't exist yet (e.g. no `projects/` directory at all) — the
    /// enumerator guard right after this call handles that case.
    private static func resolvedPath(_ url: URL) -> URL {
        var buffer = [Int8](repeating: 0, count: Int(PATH_MAX))
        guard realpath(url.path, &buffer) != nil else { return url }
        return URL(fileURLWithPath: String(cString: buffer))
    }

    private static func isWithin(day: String, cutoffDayKey: String?) -> Bool {
        guard let cutoffDayKey else { return true }
        return day >= cutoffDayKey
    }

    private static func updatedCache(
        existing: FileParseCache?,
        fileURL: URL,
        mtime: Date,
        size: Int64,
        pathSessionId: String?
    ) -> FileParseCache {
        if let existing, existing.mtime == mtime, existing.size == size,
           existing.parsedByteOffset == size {
            return existing
        }

        if let existing, size >= existing.size {
            let appended = parseByteRange(
                fileURL: fileURL,
                from: existing.parsedByteOffset,
                pathSessionId: pathSessionId,
                seenDedupKeys: existing.seenDedupKeys
            )
            var mergedBuckets = existing.dailyBuckets
            for (day, bucket) in appended.buckets {
                mergedBuckets[day, default: DayAggregate()].merge(bucket)
            }
            return FileParseCache(
                mtime: mtime,
                size: size,
                parsedByteOffset: appended.offset,
                dailyBuckets: mergedBuckets,
                seenDedupKeys: appended.seenDedupKeys
            )
        }

        // No existing entry, or the file shrank (truncated/rewritten) — full reparse with a
        // fresh dedup set, since prior seen keys aren't known to match this file's content.
        let full = parseByteRange(fileURL: fileURL, from: 0, pathSessionId: pathSessionId, seenDedupKeys: [])
        return FileParseCache(
            mtime: mtime,
            size: size,
            parsedByteOffset: full.offset,
            dailyBuckets: full.buckets,
            seenDedupKeys: full.seenDedupKeys
        )
    }

    // swiftlint:disable large_tuple
    /// Parses only complete (newline-terminated) lines, leaving any unterminated trailing line
    /// unread so a later scan can pick it back up once the writer finishes it. A complete line
    /// that still fails JSON decoding is skipped as malformed. `seenDedupKeys` is seeded from the
    /// caller's persisted `FileParseCache` and returned updated, so a duplicate straddling two
    /// separate incremental scans is still caught.
    private static func parseByteRange(
        fileURL: URL,
        from byteOffset: Int64,
        pathSessionId: String?,
        seenDedupKeys: Set<DedupKey>
    ) -> (buckets: [String: DayAggregate], offset: Int64, seenDedupKeys: Set<DedupKey>) {
        // swiftlint:enable large_tuple
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return ([:], byteOffset, seenDedupKeys) }
        defer { try? handle.close() }

        let data: Data?
        do {
            try handle.seek(toOffset: UInt64(byteOffset))
            data = try handle.readToEnd()
        } catch {
            return ([:], byteOffset, seenDedupKeys)
        }

        guard let data, !data.isEmpty else { return ([:], byteOffset, seenDedupKeys) }

        // No complete line anywhere in this read — leave the offset untouched so the whole,
        // still-unterminated chunk is retried next scan.
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return ([:], byteOffset, seenDedupKeys) }

        let complete = data[data.startIndex...lastNewline]
        guard let content = String(data: complete, encoding: .utf8) else { return ([:], byteOffset, seenDedupKeys) }

        let lines = content.components(separatedBy: "\n")
        var buckets: [String: DayAggregate] = [:]
        var dedup = TokenDeduplicator(seenKeys: seenDedupKeys)

        for line in lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let entry = try? JSONDecoder().decode(SessionEntry.self, from: lineData),
                  entry.message?.role == "assistant",
                  let usage = entry.message?.usage,
                  let resolvedSessionId = pathSessionId ?? entry.sessionId,
                  dedup.shouldCount(messageId: entry.message?.id, requestId: entry.requestId) else {
                continue
            }

            // Entries with no parsable timestamp fall back to the file's own mtime's day rather
            // than being dropped — matches the "don't silently lose tokens" stance elsewhere in
            // this parser, adapted to a model that needs a concrete day to bucket into.
            let entryDate = entry.timestamp.flatMap(parseISO8601) ?? mtimeFallback(for: fileURL)
            let key = dayKey(for: entryDate)

            var bucket = buckets[key] ?? DayAggregate()
            bucket.sessionIds.insert(resolvedSessionId)
            bucket.input += usage.inputTokens ?? 0
            bucket.output += usage.outputTokens ?? 0
            bucket.cacheCreation += usage.cacheCreationTokens ?? 0
            bucket.cacheRead += usage.cacheReadTokens ?? 0
            buckets[key] = bucket
        }

        return (buckets, byteOffset + Int64(complete.count), dedup.seenKeys)
    }

    private static func mtimeFallback(for fileURL: URL) -> Date {
        (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
    }

    private static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

// MARK: - Persistence

enum TranscriptCachePersistence {
    static var defaultFileURL: URL {
        // swiftlint:disable:next force_unwrapping
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Spark")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("transcript-cache.json")
    }

    static func load(from url: URL = defaultFileURL) -> TranscriptCacheStore {
        guard let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(TranscriptCacheStore.self, from: data),
              store.schemaVersion == TranscriptCacheStore.currentSchemaVersion else {
            return .empty
        }
        return store
    }

    static func save(_ store: TranscriptCacheStore, to url: URL = defaultFileURL) {
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: url)
        }
    }
}

// MARK: - Concurrency-safe production entry point

/// Serializes access to the shared in-memory + on-disk cache so overlapping stats refreshes
/// (e.g. a rapid period switch while a broader-period scan is still running) can't race on it.
actor LiveTranscriptCache {
    static let shared = LiveTranscriptCache()

    private var store: TranscriptCacheStore?

    // swiftlint:disable large_tuple
    func aggregate(
        claudeDir: URL,
        cutoff: Date?
    ) -> (sessionIds: Set<String>, input: Int, output: Int, cacheCreation: Int, cacheRead: Int) {
        // swiftlint:enable large_tuple
        var current = store ?? TranscriptCachePersistence.load()
        let result = TranscriptCache.aggregate(claudeDir: claudeDir, cutoff: cutoff, store: &current)
        store = current
        TranscriptCachePersistence.save(current)
        return result
    }
}
