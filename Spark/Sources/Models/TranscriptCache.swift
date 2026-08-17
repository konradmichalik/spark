import Foundation

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
        let cwd: String?
    }

    struct SessionMessage: Decodable {
        let id: String?
        let role: String?
        let model: String?
        let usage: TokenUsage?
    }

    /// Locally generated messages (e.g. API error notices) rather than billable inference —
    /// must never appear as a model in the per-model breakdown.
    static let syntheticModelMarker = "<synthetic>"

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

    /// Skips assistant entries that share a `(message.id, requestId)` pair already seen while
    /// parsing one file. Claude Code writes duplicate usage-bearing entries for a single response
    /// (one per streamed block, e.g. text + tool_use), each carrying the identical `usage`
    /// payload. Scoped per file rather than across the whole scan (unlike a from-scratch parse):
    /// every duplicate pair observed in practice shares a single transcript file, and per-file
    /// scoping is what makes independent incremental re-parsing of one file possible.
    struct TokenDeduplicator {
        private var seenKeys: Set<String> = []

        /// Entries missing either field are always counted, so an unexpected schema change
        /// doesn't silently drop their tokens instead of merely failing to dedupe them.
        mutating func shouldCount(messageId: String?, requestId: String?) -> Bool {
            guard let messageId, let requestId else { return true }
            return seenKeys.insert("\(messageId):\(requestId)").inserted
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

    /// The encoded project directory name a transcript file lives under — the first path
    /// component under `projects/`, for both session files and their subagent transcripts.
    static func projectKey(forTranscriptAt url: URL, projectsDir: URL) -> String? {
        let relative = Array(url.pathComponents.dropFirst(projectsDir.pathComponents.count))
        return relative.count >= 2 ? relative[0] : nil
    }

    /// Scans every transcript under `claudeDir/projects`, updating `store` in place, and returns
    /// totals filtered to `cutoff` (`nil` = all-time). Files whose cache entry already matches
    /// their on-disk mtime/size are never opened.
    static func aggregate(
        claudeDir: URL,
        cutoff: Date?,
        store: inout TranscriptCacheStore
    ) -> TranscriptTotals {
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
            return TranscriptTotals()
        }

        let cutoffDayKey = cutoff.map { dayKey(for: $0) }
        var totals = TranscriptTotals()

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            processFile(fileURL, projectsDir: projectsDir, cutoffDayKey: cutoffDayKey, store: &store, totals: &totals)
        }

        return totals
    }

    private static func processFile(
        _ fileURL: URL,
        projectsDir: URL,
        cutoffDayKey: String?,
        store: inout TranscriptCacheStore,
        totals: inout TranscriptTotals
    ) {
        guard let resourceValues = try? fileURL.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey]
        ),
            let mtime = resourceValues.contentModificationDate,
            let size = resourceValues.fileSize else {
            return
        }

        let path = fileURL.path
        let project = projectKey(forTranscriptAt: fileURL, projectsDir: projectsDir)
        let updated = updatedCache(
            existing: store.files[path],
            fileURL: fileURL,
            mtime: mtime,
            size: Int64(size),
            pathSessionId: sessionId(forTranscriptAt: fileURL, projectsDir: projectsDir)
        )
        store.files[path] = updated

        if let project, let cwd = updated.discoveredCwd, totals.projectDisplayNames[project] == nil {
            totals.projectDisplayNames[project] = cwd
        }

        for (day, bucket) in updated.dailyBuckets where isWithin(day: day, cutoffDayKey: cutoffDayKey) {
            totals.sessionIds.formUnion(bucket.sessionIds)
            totals.input += bucket.input
            totals.output += bucket.output
            totals.cacheCreation += bucket.cacheCreation
            totals.cacheRead += bucket.cacheRead
            for (model, modelTotals) in bucket.perModel {
                totals.modelTotals[model, default: ModelTokenTotals()].merge(modelTotals)
            }
            if let project {
                totals.projectTotals[project, default: ProjectTokenTotals()].merge(ProjectTokenTotals(
                    input: bucket.input,
                    output: bucket.output,
                    cacheCreation: bucket.cacheCreation,
                    cacheRead: bucket.cacheRead
                ))
            }
        }
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
        if let existing, existing.mtime == mtime, existing.size == size {
            return existing
        }

        if let existing, size >= existing.size {
            let appended = parseByteRange(
                fileURL: fileURL,
                from: existing.parsedByteOffset,
                pathSessionId: pathSessionId
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
                discoveredCwd: existing.discoveredCwd ?? appended.discoveredCwd
            )
        }

        // No existing entry, or the file shrank (truncated/rewritten) — full reparse.
        let full = parseByteRange(fileURL: fileURL, from: 0, pathSessionId: pathSessionId)
        return FileParseCache(
            mtime: mtime,
            size: size,
            parsedByteOffset: full.offset,
            dailyBuckets: full.buckets,
            discoveredCwd: full.discoveredCwd
        )
    }

    // swiftlint:disable large_tuple
    /// Parses every line from `byteOffset` to end of file. A line still being written when this
    /// runs (rare — the writer hasn't flushed its closing newline yet) fails JSON decoding and is
    /// silently skipped, same as any other malformed line — including on the next scan, since the
    /// returned offset advances past every byte read here regardless of per-line decode success.
    private static func parseByteRange(
        fileURL: URL,
        from byteOffset: Int64,
        pathSessionId: String?
    ) -> (buckets: [String: DayAggregate], offset: Int64, discoveredCwd: String?) {
        // swiftlint:enable large_tuple
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return ([:], byteOffset, nil)
        }
        defer { try? handle.close() }

        let data: Data?
        do {
            try handle.seek(toOffset: UInt64(byteOffset))
            data = try handle.readToEnd()
        } catch {
            return ([:], byteOffset, nil)
        }

        guard let data, !data.isEmpty, let content = String(data: data, encoding: .utf8) else {
            return ([:], byteOffset, nil)
        }

        let lines = content.components(separatedBy: "\n")
        var buckets: [String: DayAggregate] = [:]
        var dedup = TokenDeduplicator()
        var discoveredCwd: String?

        for line in lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let entry = try? JSONDecoder().decode(SessionEntry.self, from: lineData) else {
                continue
            }

            // `cwd` can appear on any entry type, not only assistant messages — captured
            // independently of the token-counting guard below.
            if discoveredCwd == nil, let cwd = entry.cwd, !cwd.isEmpty {
                discoveredCwd = cwd
            }

            guard entry.message?.role == "assistant",
                  let usage = entry.message?.usage,
                  let resolvedSessionId = pathSessionId ?? entry.sessionId,
                  dedup.shouldCount(messageId: entry.message?.id, requestId: entry.requestId) else {
                continue
            }

            recordAssistantEntry(entry, usage: usage, resolvedSessionId: resolvedSessionId, fileURL: fileURL, into: &buckets)
        }

        return (buckets, byteOffset + Int64(data.count), discoveredCwd)
    }

    private static func recordAssistantEntry(
        _ entry: SessionEntry,
        usage: TokenUsage,
        resolvedSessionId: String,
        fileURL: URL,
        into buckets: inout [String: DayAggregate]
    ) {
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

        if let model = entry.message?.model, model != syntheticModelMarker {
            bucket.perModel[model, default: ModelTokenTotals()].merge(ModelTokenTotals(
                input: usage.inputTokens ?? 0,
                output: usage.outputTokens ?? 0,
                cacheCreation: usage.cacheCreationTokens ?? 0,
                cacheRead: usage.cacheReadTokens ?? 0
            ))
        }

        buckets[key] = bucket
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
