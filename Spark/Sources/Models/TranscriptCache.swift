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

    /// The encoded project directory name a transcript file lives under — the first path
    /// component under `projects/`, for both session files and their subagent transcripts.
    static func projectKey(forTranscriptAt url: URL, projectsDir: URL) -> String? {
        let relative = Array(url.pathComponents.dropFirst(projectsDir.pathComponents.count))
        return relative.count >= 2 ? relative[0] : nil
    }

    /// Scans every transcript under `claudeDir/projects`, updating `store` in place, and returns
    /// totals filtered to `cutoff...upperCutoff` (either `nil` leaves that side unbounded). Files
    /// whose cache entry already matches their on-disk mtime/size are never opened — every file is
    /// always parsed in full into per-day buckets regardless of the bound, so a bounded scan (e.g.
    /// a past week) costs no extra I/O over an unbounded one; the bound is applied only when
    /// summing the already-cached buckets below.
    static func aggregate(
        claudeDir: URL,
        cutoff: Date?,
        upperCutoff: Date? = nil,
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
        let upperCutoffDayKey = upperCutoff.map { dayKey(for: $0) }
        var totals = TranscriptTotals()

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            guard let resourceValues = try? fileURL.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey]
            ),
                let mtime = resourceValues.contentModificationDate,
                let size = resourceValues.fileSize else {
                continue
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

            for (day, bucket) in updated.dailyBuckets
            where isWithin(day: day, cutoffDayKey: cutoffDayKey, upperCutoffDayKey: upperCutoffDayKey) {
                accumulate(bucket: bucket, project: project, into: &totals)
            }
        }

        return totals
    }

    private static func accumulate(bucket: DayAggregate, project: String?, into totals: inout TranscriptTotals) {
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

    /// Fully resolves symlinks via `realpath(3)`, unlike `URL.resolvingSymlinksInPath()` which
    /// intentionally preserves BSD alias roots (`/var`, `/tmp`, `/etc`). Falls back to the
    /// original URL if the path doesn't exist yet (e.g. no `projects/` directory at all) — the
    /// enumerator guard right after this call handles that case.
    ///
    /// Internal (not private): `ActiveSessionResolver` must resolve each `claudeDir/projects`
    /// root identically to how `aggregate` indexed `store.files`, since session-ID derivation is
    /// depth-based and silently returns `nil` if the two disagree.
    static func resolvedPath(_ url: URL) -> URL {
        var buffer = [Int8](repeating: 0, count: Int(PATH_MAX))
        guard realpath(url.path, &buffer) != nil else { return url }
        return URL(fileURLWithPath: String(cString: buffer))
    }

    private static func isWithin(day: String, cutoffDayKey: String?, upperCutoffDayKey: String? = nil) -> Bool {
        if let cutoffDayKey, day < cutoffDayKey { return false }
        if let upperCutoffDayKey, day > upperCutoffDayKey { return false }
        return true
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
                seenDedupKeys: existing.seenDedupKeys,
                lastContextTokens: existing.lastContextTokens
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
                seenDedupKeys: appended.seenDedupKeys,
                discoveredCwd: existing.discoveredCwd ?? appended.discoveredCwd,
                lastContextTokens: appended.lastContextTokens
            )
        }

        // No existing entry, or the file shrank (truncated/rewritten) — full reparse with a
        // fresh dedup set, since prior seen keys aren't known to match this file's content.
        let full = parseByteRange(fileURL: fileURL, from: 0, pathSessionId: pathSessionId, seenDedupKeys: [], lastContextTokens: nil)
        return FileParseCache(
            mtime: mtime,
            size: size,
            parsedByteOffset: full.offset,
            dailyBuckets: full.buckets,
            seenDedupKeys: full.seenDedupKeys,
            discoveredCwd: full.discoveredCwd,
            lastContextTokens: full.lastContextTokens
        )
    }

    /// One incremental parse's result — a struct, not a tuple, once a fifth member arrived.
    private struct ParseResult {
        var buckets: [String: DayAggregate] = [:]
        var offset: Int64
        var seenDedupKeys: Set<DedupKey>
        var discoveredCwd: String?
        var lastContextTokens: Int?
    }

    /// Parses only complete (newline-terminated) lines, leaving any unterminated trailing line
    /// unread so a later scan can pick it back up once the writer finishes it. A complete line
    /// that still fails JSON decoding is skipped as malformed. `seenDedupKeys` and
    /// `lastContextTokens` are seeded from the caller's `FileParseCache` and carried through
    /// `empty` on every early return, so both survive across separate incremental scans.
    private static func parseByteRange(
        fileURL: URL,
        from byteOffset: Int64,
        pathSessionId: String?,
        seenDedupKeys: Set<DedupKey>,
        lastContextTokens: Int?
    ) -> ParseResult {
        let empty = ParseResult(offset: byteOffset, seenDedupKeys: seenDedupKeys, lastContextTokens: lastContextTokens)

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return empty }
        defer { try? handle.close() }

        let data: Data?
        do {
            try handle.seek(toOffset: UInt64(byteOffset))
            data = try handle.readToEnd()
        } catch {
            return empty
        }

        guard let data, !data.isEmpty else { return empty }

        // No complete line anywhere in this read — leave the offset untouched so the whole,
        // still-unterminated chunk is retried next scan.
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return empty }

        let complete = data[data.startIndex...lastNewline]
        guard let content = String(data: complete, encoding: .utf8) else { return empty }

        let lines = content.components(separatedBy: "\n")
        var state = LineParseState(dedup: TokenDeduplicator(seenKeys: seenDedupKeys), lastContextTokens: lastContextTokens)

        for line in lines {
            processLine(line, fileURL: fileURL, pathSessionId: pathSessionId, state: &state)
        }

        return ParseResult(
            buckets: state.buckets,
            offset: byteOffset + Int64(complete.count),
            seenDedupKeys: state.dedup.seenKeys,
            discoveredCwd: state.discoveredCwd,
            lastContextTokens: state.lastContextTokens
        )
    }

    /// Mutable state threaded through one file's line-by-line parse.
    private struct LineParseState {
        var buckets: [String: DayAggregate] = [:]
        var dedup: TokenDeduplicator
        var discoveredCwd: String?
        var lastContextTokens: Int?
    }

    /// Decodes one line and folds it into `state.buckets`. Session-ID resolution must not be
    /// gated behind the same guard as token aggregation: a transcript with only a user record, or
    /// an assistant record without usage yet, is still a real session and must be counted. `cwd`
    /// can appear on any entry type, not only assistant messages, so it's captured independently.
    private static func processLine(_ line: String, fileURL: URL, pathSessionId: String?, state: inout LineParseState) {
        guard !line.isEmpty,
              let lineData = line.data(using: .utf8),
              let entry = try? JSONDecoder().decode(SessionEntry.self, from: lineData) else {
            return
        }

        if state.discoveredCwd == nil, let cwd = entry.cwd, !cwd.isEmpty {
            state.discoveredCwd = cwd
        }

        guard let resolvedSessionId = pathSessionId ?? entry.sessionId else {
            return
        }

        // Entries with no parsable timestamp fall back to the file's own mtime's day rather
        // than being dropped — matches the "don't silently lose tokens" stance elsewhere in
        // this parser, adapted to a model that needs a concrete day to bucket into.
        let entryDate = entry.timestamp.flatMap(parseISO8601) ?? mtimeFallback(for: fileURL)
        let key = dayKey(for: entryDate)

        var bucket = state.buckets[key] ?? DayAggregate()
        bucket.sessionIds.insert(resolvedSessionId)

        guard entry.message?.role == "assistant", let usage = entry.message?.usage else {
            state.buckets[key] = bucket
            return
        }

        // Outside the dedup gate below: a duplicate streamed chunk carries the same `usage`, so
        // setting this again is harmless, and it must stay correct even for a dedup-skipped turn.
        state.lastContextTokens = (usage.inputTokens ?? 0) + (usage.cacheCreationTokens ?? 0) + (usage.cacheReadTokens ?? 0)

        guard state.dedup.shouldCount(messageId: entry.message?.id, requestId: entry.requestId) else {
            state.buckets[key] = bucket
            return
        }
        bucket.input += usage.inputTokens ?? 0
        bucket.output += usage.outputTokens ?? 0
        bucket.cacheCreation += usage.cacheCreationTokens ?? 0
        bucket.cacheRead += usage.cacheReadTokens ?? 0

        applyModelAttribution(to: &bucket, entry: entry, usage: usage)

        state.buckets[key] = bucket
    }

    /// Attributes `usage` to the entry's model in `bucket.perModel`, unless the entry came from
    /// `syntheticModelMarker` (locally generated, not billable inference).
    private static func applyModelAttribution(to bucket: inout DayAggregate, entry: SessionEntry, usage: TokenUsage) {
        guard let model = entry.message?.model, model != syntheticModelMarker else { return }
        bucket.perModel[model, default: ModelTokenTotals()].merge(ModelTokenTotals(
            input: usage.inputTokens ?? 0,
            output: usage.outputTokens ?? 0,
            cacheCreation: usage.cacheCreationTokens ?? 0,
            cacheRead: usage.cacheReadTokens ?? 0
        ))
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
