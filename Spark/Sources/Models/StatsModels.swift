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
        let sessionId: String?
    }

    private struct SessionEntry: Decodable {
        let message: SessionMessage?
        let timestamp: String?
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

        // 1. Parse history.jsonl for message/session counts
        let historyURL = claudeDir.appendingPathComponent("history.jsonl")
        let (messageCount, sessionCount, sessionIds) = parseHistoryCounts(url: historyURL, period: period)

        // 2. Parse project JSONLs for token counts
        let (inputTokens, outputTokens) = parseTokenCounts(
            claudeDir: claudeDir,
            sessionIds: sessionIds,
            cutoff: period.startDate
        )

        guard messageCount > 0 else { return nil }

        return LiveStats(
            period: period,
            messageCount: messageCount,
            sessionCount: sessionCount,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }

    // swiftlint:disable large_tuple
    private static func parseHistoryCounts(
        url: URL,
        period: StatsPeriod
    ) -> (messages: Int, sessions: Int, sessionIds: Set<String>) {
        // swiftlint:enable large_tuple
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return (0, 0, [])
        }

        let startTimestamp = (period.startDate?.timeIntervalSince1970 ?? 0) * 1000
        var messageCount = 0
        var sessionIds: Set<String> = []

        for line in content.components(separatedBy: "\n").reversed() {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let entry = try? JSONDecoder().decode(HistoryEntry.self, from: lineData) else {
                continue
            }
            if entry.timestamp < startTimestamp { break }
            messageCount += 1
            if let sid = entry.sessionId {
                sessionIds.insert(sid)
            }
        }

        return (messageCount, sessionIds.count, sessionIds)
    }

    private static func parseTokenCounts(
        claudeDir: URL,
        sessionIds: Set<String>,
        cutoff: Date?
    ) -> (input: Int, output: Int) {
        let projectsDir = claudeDir.appendingPathComponent("projects")
        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: nil
        ) else {
            return (0, 0)
        }

        var totalInput = 0
        var totalOutput = 0

        for dir in projectDirs {
            for sessionId in sessionIds {
                let jsonlURL = dir.appendingPathComponent("\(sessionId).jsonl")
                guard FileManager.default.fileExists(atPath: jsonlURL.path),
                      let data = try? Data(contentsOf: jsonlURL),
                      let content = String(data: data, encoding: .utf8) else {
                    continue
                }

                for line in content.components(separatedBy: "\n") {
                    guard !line.isEmpty,
                          let lineData = line.data(using: .utf8),
                          let entry = try? JSONDecoder().decode(SessionEntry.self, from: lineData),
                          entry.message?.role == "assistant",
                          let usage = entry.message?.usage,
                          isOnOrAfter(cutoff: cutoff, timestamp: entry.timestamp) else {
                        continue
                    }
                    totalInput += usage.inputTokens ?? 0
                    totalOutput += usage.outputTokens ?? 0
                }
            }
        }

        return (totalInput, totalOutput)
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
