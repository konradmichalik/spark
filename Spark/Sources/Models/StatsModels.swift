import Foundation

// MARK: - Helpers

func formatTokenCount(_ count: Int) -> String {
    if count >= 1_000_000_000 {
        return String(format: "%.1fB", Double(count) / 1_000_000_000)
    }
    if count >= 1_000_000 {
        return String(format: "%.1fM", Double(count) / 1_000_000)
    }
    if count >= 1_000 {
        return String(format: "%.1fK", Double(count) / 1_000)
    }
    return "\(count)"
}

// MARK: - Stats Period

enum StatsPeriod: String, CaseIterable, Sendable {
    case today = "Today"
    case week = "7d"
    case month = "30d"
    case all = "All"

    /// Lower cutoff for history entries; `nil` means no cutoff (all-time).
    var startDate: Date? {
        switch self {
        case .today: Calendar.current.startOfDay(for: Date())
        case .week: Date().addingTimeInterval(-7 * 24 * 3600)
        case .month: Date().addingTimeInterval(-30 * 24 * 3600)
        case .all: nil
        }
    }
}

// MARK: - Live Stats (parsed from history.jsonl)

struct LiveStats: Sendable {
    let period: StatsPeriod
    let messageCount: Int
    let sessionCount: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    /// Total tokens per raw model ID (e.g. `claude-opus-4-6`). Kept raw here — grouping into
    /// families and display normalisation happen only at the view layer, via `ModelFamily`.
    let modelTotals: [String: Int]
    /// Total tokens per encoded project directory name (e.g. `-Users-me-app`), with the best
    /// available display name (resolved `cwd`, or the encoded key itself as a last resort) —
    /// see `ProjectFamily`.
    let projectTotals: [String: Int]
    let projectDisplayNames: [String: String]

    init(
        period: StatsPeriod,
        messageCount: Int,
        sessionCount: Int,
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationTokens: Int,
        cacheReadTokens: Int,
        modelTotals: [String: Int] = [:],
        projectTotals: [String: Int] = [:],
        projectDisplayNames: [String: String] = [:]
    ) {
        self.period = period
        self.messageCount = messageCount
        self.sessionCount = sessionCount
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.modelTotals = modelTotals
        self.projectTotals = projectTotals
        self.projectDisplayNames = projectDisplayNames
    }

    var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }

    /// Excludes cache reads — reused context, not fresh consumption. This is what's shown as the
    /// headline number; the full `totalTokens` (including cache reads) is only surfaced via
    /// `tokenBreakdown`, e.g. in a hover tooltip.
    var realTokens: Int { inputTokens + outputTokens + cacheCreationTokens }

    var formattedTokens: String {
        formatTokenCount(realTokens)
    }

    var tokenBreakdown: String {
        "Input \(formatTokenCount(inputTokens)) · Output \(formatTokenCount(outputTokens)) · " +
        "Cache write \(formatTokenCount(cacheCreationTokens)) · Cache read \(formatTokenCount(cacheReadTokens))"
    }

    /// Sum of tokens across every model in the given family — the local-attribution figure shown
    /// next to the Sonnet/Opus API buckets.
    func tokens(for family: ModelFamily) -> Int {
        modelTotals.reduce(0) { partial, entry in
            ModelFamily.family(forRawModelId: entry.key) == family ? partial + entry.value : partial
        }
    }

    /// Top projects by token volume, each with a display name resolved from `cwd` where known.
    func topProjects(limit: Int) -> [ProjectUsage] {
        projectTotals
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { key, tokens in
                ProjectUsage(
                    key: key,
                    displayName: ProjectFamily.displayName(forKey: key, cwd: projectDisplayNames[key]),
                    tokens: tokens
                )
            }
    }
}

struct ProjectUsage: Identifiable, Sendable {
    let key: String
    let displayName: String
    let tokens: Int

    var id: String { key }
}

enum LiveStatsParser {
    private struct HistoryEntry: Decodable {
        let timestamp: Double
    }

    /// Production entry point. Goes through the shared, disk-persisted transcript cache.
    static func parseStats(period: StatsPeriod) async -> LiveStats? {
        let roots = ClaudeConfigDirectory.resolveCurrent().roots
        let transcripts = await LiveTranscriptCache.shared.aggregate(claudeDirs: roots, cutoff: period.startDate)
        return makeLiveStats(period: period, claudeDirs: roots, transcripts: transcripts)
    }

    /// Test entry point with an explicit `claudeDir`, pointing at a fixture tree instead of the
    /// real `~/.claude`. Deliberately bypasses `LiveTranscriptCache.shared` — going through the
    /// disk-persisted production singleton here would pollute the real cache file (and any other
    /// test's fixture data) with throwaway test data. Uses a fresh, discarded-after-use store,
    /// so this does not exercise the incremental-caching behavior itself — see
    /// `TranscriptCacheTests` for that.
    static func parseStats(period: StatsPeriod, claudeDir: URL) -> LiveStats? {
        var store = TranscriptCacheStore.empty
        let transcripts = TranscriptCache.aggregate(claudeDir: claudeDir, cutoff: period.startDate, store: &store)
        return makeLiveStats(period: period, claudeDirs: [claudeDir], transcripts: transcripts)
    }

    private static func makeLiveStats(
        period: StatsPeriod,
        claudeDirs: [URL],
        transcripts: TranscriptTotals
    ) -> LiveStats? {
        // history.jsonl only ever backs the user-message count — it records interactive
        // prompts, not the sessions or tokens Claude Code actually spent (see #46).
        let messageCount = claudeDirs.reduce(0) { total, claudeDir in
            let historyURL = claudeDir.appendingPathComponent("history.jsonl")
            return total + parseMessageCount(url: historyURL, period: period)
        }

        guard messageCount > 0 || !transcripts.sessionIds.isEmpty else { return nil }

        return LiveStats(
            period: period,
            messageCount: messageCount,
            sessionCount: transcripts.sessionIds.count,
            inputTokens: transcripts.input,
            outputTokens: transcripts.output,
            cacheCreationTokens: transcripts.cacheCreation,
            cacheReadTokens: transcripts.cacheRead,
            modelTotals: transcripts.modelTotals.mapValues { $0.real },
            projectTotals: transcripts.projectTotals.mapValues { $0.real },
            projectDisplayNames: transcripts.projectDisplayNames
        )
    }

    private static func parseMessageCount(url: URL, period: StatsPeriod) -> Int {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return 0
        }

        let startTimestamp = (period.startDate?.timeIntervalSince1970 ?? 0) * 1000
        var messageCount = 0

        for line in content.components(separatedBy: "\n").reversed() {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let entry = try? JSONDecoder().decode(HistoryEntry.self, from: lineData) else {
                continue
            }
            if entry.timestamp < startTimestamp { break }
            messageCount += 1
        }

        return messageCount
    }
}
