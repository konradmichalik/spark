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

    var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }

    var formattedTokens: String {
        formatTokenCount(totalTokens)
    }

    var tokenBreakdown: String {
        "Input \(formatTokenCount(inputTokens)) · Output \(formatTokenCount(outputTokens)) · " +
        "Cache write \(formatTokenCount(cacheCreationTokens)) · Cache read \(formatTokenCount(cacheReadTokens))"
    }
}

enum LiveStatsParser {
    private struct HistoryEntry: Decodable {
        let timestamp: Double
    }

    /// Production entry point. Goes through the shared, disk-persisted transcript cache.
    static func parseStats(period: StatsPeriod) async -> LiveStats? {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let transcripts = await LiveTranscriptCache.shared.aggregate(claudeDir: claudeDir, cutoff: period.startDate)
        return makeLiveStats(period: period, claudeDir: claudeDir, transcripts: transcripts)
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
        return makeLiveStats(period: period, claudeDir: claudeDir, transcripts: transcripts)
    }

    // swiftlint:disable large_tuple
    private static func makeLiveStats(
        period: StatsPeriod,
        claudeDir: URL,
        transcripts: (sessionIds: Set<String>, input: Int, output: Int, cacheCreation: Int, cacheRead: Int)
    ) -> LiveStats? {
        // swiftlint:enable large_tuple
        // history.jsonl only ever backs the user-message count — it records interactive
        // prompts, not the sessions or tokens Claude Code actually spent (see #46).
        let historyURL = claudeDir.appendingPathComponent("history.jsonl")
        let messageCount = parseMessageCount(url: historyURL, period: period)

        guard messageCount > 0 || !transcripts.sessionIds.isEmpty else { return nil }

        return LiveStats(
            period: period,
            messageCount: messageCount,
            sessionCount: transcripts.sessionIds.count,
            inputTokens: transcripts.input,
            outputTokens: transcripts.output,
            cacheCreationTokens: transcripts.cacheCreation,
            cacheReadTokens: transcripts.cacheRead
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
