import Foundation

/// A Claude Code session with a transcript write inside the active window — see
/// `ActiveSessionResolver.resolve(files:projectsDirs:now:window:)`. Derived on every refresh from
/// the already-cached `FileParseCache` entries; nothing here is itself persisted.
struct ActiveSession: Identifiable, Equatable, Sendable {
    let sessionId: String
    let projectKey: String
    let displayName: String
    let lastActivity: Date
    /// The session's working directory, when a transcript line has revealed one — `nil` falls
    /// back to `displayName`'s lossy derivation from the encoded project key, in which case
    /// there's no real path to reveal in Finder.
    let cwd: String?
    /// A short session-ID prefix, set only when another active session shares this project and
    /// the rows would otherwise be indistinguishable. Kept separate from `displayName` so the
    /// view can render it as secondary text instead of letting hex noise sit at the same visual
    /// weight as the project name.
    let sessionIdSuffix: String?
    /// An approximation of the session's current context-window size — see
    /// `FileParseCache.lastContextTokens`. Always read from the root session file, never a
    /// subagent's: a subagent runs its own separate, smaller conversation, so its context size
    /// would misrepresent the main conversation shown by `displayName`.
    let contextTokens: Int?

    init(
        sessionId: String,
        projectKey: String,
        displayName: String,
        lastActivity: Date,
        cwd: String? = nil,
        sessionIdSuffix: String? = nil,
        contextTokens: Int? = nil
    ) {
        self.sessionId = sessionId
        self.projectKey = projectKey
        self.displayName = displayName
        self.lastActivity = lastActivity
        self.cwd = cwd
        self.sessionIdSuffix = sessionIdSuffix
        self.contextTokens = contextTokens
    }

    var id: String { sessionId }

    /// How long ago this session last wrote, or `nil` while it's still fresh. Returning `nil`
    /// rather than an "active now" string is deliberate: every row in a list of *active* sessions
    /// would carry that same string, so it reads as a repeated rail carrying no information. The
    /// column earns its place only once a session starts aging toward the end of the window.
    ///
    /// Negative elapsed (a slightly-future mtime, within the resolver's clock-skew tolerance) is
    /// clamped to zero, so it reads as fresh rather than as "in -3s".
    func activityLabel(now: Date = Date()) -> String? {
        let elapsed = max(0, now.timeIntervalSince(lastActivity))
        if elapsed < 30 { return nil }
        if elapsed < 60 { return "\(Int(elapsed))s" }
        return "\(Int(elapsed / 60))m"
    }

    /// Whether this session wrote recently enough that no elapsed time is worth showing. Defined
    /// in terms of `activityLabel` rather than repeating its threshold, so the row's status dot
    /// and its trailing label can never disagree about the same session.
    func isFresh(now: Date = Date()) -> Bool {
        activityLabel(now: now) == nil
    }
}

/// Derives the currently active sessions purely from already-cached file metadata (`mtime`,
/// `discoveredCwd`) — no file I/O, no JSONL parsing. A session is "active" only in the sense that
/// its transcript (or one of its subagents' transcripts) was written to within `window` seconds;
/// there is no explicit "session ended" signal in the data, so this is deliberately never treated
/// as anything stronger than a recency heuristic.
enum ActiveSessionResolver {
    static let defaultWindow: TimeInterval = 300

    /// A file whose mtime is more than this far in the future is treated as bad clock data rather
    /// than "active forever" — see `resolve`'s window check.
    private static let clockSkewTolerance: TimeInterval = 60

    /// A root session file's path depth relative to `projectsDir` (`<project>/<uuid>.jsonl`) — a
    /// subagent file (`<project>/<uuid>/subagents/agent-*.jsonl`) is depth 4. See
    /// `TranscriptCache.sessionId(forTranscriptAt:projectsDir:)`, which this mirrors.
    private static let rootFileDepth = 2

    private struct SessionAccumulator {
        var lastActivity: Date
        var projectKey: String
        var cwd: String?
        var cwdDepth: Int
        var contextTokens: Int?
    }

    static func resolve(
        files: [String: FileParseCache],
        projectsDirs: [URL],
        now: Date = Date(),
        window: TimeInterval = defaultWindow
    ) -> [ActiveSession] {
        var bySession: [String: SessionAccumulator] = [:]

        for (path, fileCache) in files {
            let elapsed = now.timeIntervalSince(fileCache.mtime)
            guard elapsed <= window, elapsed >= -clockSkewTolerance else { continue }
            accumulate(path: path, fileCache: fileCache, projectsDirs: projectsDirs, into: &bySession)
        }

        return buildSessions(from: bySession)
    }

    private static func accumulate(
        path: String,
        fileCache: FileParseCache,
        projectsDirs: [URL],
        into bySession: inout [String: SessionAccumulator]
    ) {
        guard let projectsDir = projectsDirs.first(where: { path.hasPrefix($0.path + "/") }) else { return }

        let fileURL = URL(fileURLWithPath: path)
        guard let sessionId = TranscriptCache.sessionId(forTranscriptAt: fileURL, projectsDir: projectsDir),
              let projectKey = TranscriptCache.projectKey(forTranscriptAt: fileURL, projectsDir: projectsDir) else {
            return
        }

        let depth = fileURL.pathComponents.count - projectsDir.pathComponents.count
        var entry = bySession[sessionId] ?? SessionAccumulator(
            lastActivity: fileCache.mtime,
            projectKey: projectKey,
            cwd: nil,
            cwdDepth: Int.max
        )
        entry.lastActivity = max(entry.lastActivity, fileCache.mtime)
        // A root session file (depth 2) wins over a subagent file (depth 4) for the display name,
        // falling back to a subagent's cwd only when the root hasn't revealed one yet.
        if let discoveredCwd = fileCache.discoveredCwd, depth < entry.cwdDepth {
            entry.cwd = discoveredCwd
            entry.cwdDepth = depth
        }
        // Context size, unlike cwd, has no such fallback: a subagent's is a separate, smaller
        // conversation, so showing it in place of a not-yet-available root value would misrepresent
        // the main conversation rather than merely approximate it. Only the root file may set this.
        if depth == Self.rootFileDepth, let lastContextTokens = fileCache.lastContextTokens {
            entry.contextTokens = lastContextTokens
        }
        bySession[sessionId] = entry
    }

    private static func buildSessions(from bySession: [String: SessionAccumulator]) -> [ActiveSession] {
        let projectCounts = Dictionary(grouping: bySession.values, by: \.projectKey).mapValues(\.count)

        return bySession
            .map { sessionId, entry -> ActiveSession in
                // Two concurrent sessions in the same project would otherwise render as two
                // identical rows — carry a disambiguator only when that actually happens.
                let isAmbiguous = (projectCounts[entry.projectKey] ?? 1) > 1
                return ActiveSession(
                    sessionId: sessionId,
                    projectKey: entry.projectKey,
                    displayName: ProjectFamily.displayName(forKey: entry.projectKey, cwd: entry.cwd),
                    lastActivity: entry.lastActivity,
                    cwd: entry.cwd,
                    sessionIdSuffix: isAmbiguous ? String(sessionId.prefix(8)) : nil,
                    contextTokens: entry.contextTokens
                )
            }
            .sorted { lhs, rhs in
                lhs.lastActivity != rhs.lastActivity ? lhs.lastActivity > rhs.lastActivity : lhs.sessionId < rhs.sessionId
            }
    }
}
