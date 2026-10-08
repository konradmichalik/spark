import Foundation

// MARK: - Helpers

/// USD with cents, in en_US grouping so the `$` amounts read the same in every system locale.
func formatCost(_ dollars: Double) -> String {
    if dollars > 0, dollars < 0.01 { return "<$0.01" }
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    return formatter.string(from: NSNumber(value: dollars)) ?? "$0.00"
}

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

extension StatsPeriod: SegmentLabeled {
    var segmentLabel: String { rawValue }
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
    /// The full per-model split, cache reads included, which `modelTotals` leaves out. The cost
    /// estimate needs it because cache reads are billed too.
    let modelTokenTotals: [String: ModelTokenTotals]
    let projectModelTotals: [String: [String: ModelTokenTotals]]
    let sessionTotals: [String: SessionTotals]
    /// Days of the period on which tokens were used; the divisor of "per active day" averages.
    let activeDayCount: Int
    /// Fresh tokens per day key, for the report's activity calendar.
    let dayTokens: [String: Int]

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
        projectDisplayNames: [String: String] = [:],
        modelTokenTotals: [String: ModelTokenTotals] = [:],
        projectModelTotals: [String: [String: ModelTokenTotals]] = [:],
        sessionTotals: [String: SessionTotals] = [:],
        activeDayCount: Int = 0,
        dayTokens: [String: Int] = [:]
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
        self.modelTokenTotals = modelTokenTotals
        self.projectModelTotals = projectModelTotals
        self.sessionTotals = sessionTotals
        self.activeDayCount = activeDayCount
        self.dayTokens = dayTokens
    }

    var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }

    /// Excludes cache reads — reused context, not fresh consumption. This is what's shown as the
    /// headline number; the full `totalTokens` (including cache reads) is only surfaced via
    /// `tokenBreakdown`, e.g. in a hover tooltip.
    var realTokens: Int { inputTokens + outputTokens + cacheCreationTokens }

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
    /// Projects without fresh tokens (cache reads only) are left out, they would show as 0.
    func topProjects(limit: Int) -> [ProjectUsage] {
        projectTotals
            .filter { $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map { key, tokens in
                ProjectUsage(
                    key: key,
                    displayName: ProjectFamily.displayName(forKey: key, cwd: projectDisplayNames[key]),
                    tokens: tokens,
                    cwd: projectDisplayNames[key]
                )
            }
    }

    /// Top sessions by the same token measure as `topProjects`.
    func topSessions(limit: Int) -> [SessionUsage] {
        sessionTotals
            .filter { $0.value.real > 0 }
            .sorted { $0.value.real != $1.value.real ? $0.value.real > $1.value.real : $0.key < $1.key }
            .prefix(limit)
            .map { id, session in
                SessionUsage(
                    id: id,
                    displayName: ProjectFamily.displayName(forKey: session.projectKey, cwd: projectDisplayNames[session.projectKey]),
                    tokens: session.real,
                    start: session.activity?.first,
                    duration: session.activity?.duration
                )
            }
    }
}

struct SessionUsage: Identifiable, Sendable {
    /// The session ID, also the key into `CostSummary.bySession`.
    let id: String
    let displayName: String
    let tokens: Int
    let start: Date?
    let duration: TimeInterval?
}

struct ProjectUsage: Identifiable, Sendable {
    let key: String
    let displayName: String
    let tokens: Int
    /// The project's working directory, when a transcript line has revealed one — `nil` falls
    /// back to `displayName`'s lossy derivation from the encoded project key, in which case
    /// there's no real path to reveal in Finder or copy.
    let cwd: String?

    init(key: String, displayName: String, tokens: Int, cwd: String? = nil) {
        self.key = key
        self.displayName = displayName
        self.tokens = tokens
        self.cwd = cwd
    }

    var id: String { key }
}

enum LiveStatsParser {
    private struct HistoryEntry: Decodable {
        let timestamp: Double
    }

    /// Production entry point. Goes through the shared, disk-persisted transcript cache.
    ///
    /// `cutoffOverride` lets a caller align the scan to a window other than `period`'s own
    /// fixed cutoff — e.g. the Weekly Report aligning this scan to the same calendar days its
    /// rollup-based totals sum over, rather than `.week`'s rolling "7*24h ago" cutoff.
    /// `upperCutoff` additionally bounds the scan's far end — e.g. a past week the Weekly Report
    /// is navigated back to, which must not pick up any later week's activity.
    static func parseStats(period: StatsPeriod, cutoffOverride: Date? = nil, upperCutoff: Date? = nil) async -> LiveStats? {
        let roots = ClaudeConfigDirectory.resolveCurrent().roots
        let transcripts = await LiveTranscriptCache.shared.aggregate(
            claudeDirs: roots,
            cutoff: cutoffOverride ?? period.startDate,
            upperCutoff: upperCutoff
        )
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
            projectDisplayNames: transcripts.projectDisplayNames,
            modelTokenTotals: transcripts.modelTotals,
            projectModelTotals: transcripts.projectModelTotals,
            sessionTotals: transcripts.sessionTotals,
            activeDayCount: transcripts.activeDays.count,
            dayTokens: transcripts.dayTokens
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
