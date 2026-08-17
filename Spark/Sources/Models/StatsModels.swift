import Foundation

// MARK: - Helpers

func formatTokenCount(_ count: Int) -> String {
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

    var totalTokens: Int { inputTokens + outputTokens }

    var formattedTokens: String {
        formatTokenCount(totalTokens)
    }
}

enum LiveStatsParser {
    private struct HistoryEntry: Decodable {
        let timestamp: Double
    }

    private struct SessionEntry: Decodable {
        let message: SessionMessage?
        let timestamp: String?
        let sessionId: String?
    }

    private struct SessionMessage: Decodable {
        let role: String?
        let usage: TokenUsage?
    }

    private struct TokenUsage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        // swiftlint:disable:next nesting
        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    static func parseStats(period: StatsPeriod) -> LiveStats? {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        return parseStats(period: period, claudeDir: claudeDir)
    }

    /// Exposed with an explicit `claudeDir` so tests can point it at a fixture tree instead of
    /// the real `~/.claude`.
    static func parseStats(period: StatsPeriod, claudeDir: URL) -> LiveStats? {
        // history.jsonl only ever backs the user-message count — it records interactive
        // prompts, not the sessions or tokens Claude Code actually spent (see #46).
        let historyURL = claudeDir.appendingPathComponent("history.jsonl")
        let messageCount = parseMessageCount(url: historyURL, period: period)

        let transcripts = parseTranscripts(claudeDir: claudeDir, cutoff: period.startDate)

        guard messageCount > 0 || !transcripts.sessionIds.isEmpty else { return nil }

        return LiveStats(
            period: period,
            messageCount: messageCount,
            sessionCount: transcripts.sessionIds.count,
            inputTokens: transcripts.input,
            outputTokens: transcripts.output
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
    private static func parseTranscripts(
        claudeDir: URL,
        cutoff: Date?
    ) -> (sessionIds: Set<String>, input: Int, output: Int) {
        // swiftlint:enable large_tuple
        let projectsDir = claudeDir.appendingPathComponent("projects")
        guard let enumerator = FileManager.default.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return ([], 0, 0)
        }

        var sessionIds: Set<String> = []
        var totalInput = 0
        var totalOutput = 0

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            guard let data = try? Data(contentsOf: fileURL),
                  let content = String(data: data, encoding: .utf8) else {
                continue
            }
            let pathSessionId = sessionId(forTranscriptAt: fileURL, projectsDir: projectsDir)

            for line in content.components(separatedBy: "\n") {
                guard !line.isEmpty,
                      let lineData = line.data(using: .utf8),
                      let entry = try? JSONDecoder().decode(SessionEntry.self, from: lineData),
                      entry.message?.role == "assistant",
                      let usage = entry.message?.usage,
                      isOnOrAfter(cutoff: cutoff, timestamp: entry.timestamp),
                      let resolvedSessionId = pathSessionId ?? entry.sessionId else {
                    continue
                }
                sessionIds.insert(resolvedSessionId)
                totalInput += usage.inputTokens ?? 0
                totalOutput += usage.outputTokens ?? 0
            }
        }

        return (sessionIds, totalInput, totalOutput)
    }

    /// Whether a session message falls on or after `cutoff`. Messages with no cutoff (`.all`
    /// period) or an unparsable timestamp are kept — an unparsable timestamp shouldn't silently
    /// drop tokens that would otherwise count toward the total.
    private static func isOnOrAfter(cutoff: Date?, timestamp: String?) -> Bool {
        guard let cutoff else { return true }
        guard let timestamp, let date = parseISO8601(timestamp) else { return true }
        return date >= cutoff
    }

    private static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
