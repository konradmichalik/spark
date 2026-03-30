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

// MARK: - Live Stats (parsed from history.jsonl)

struct LiveDayStats: Sendable {
    let date: String
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

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    static func parseTodayStats() -> LiveDayStats? {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")

        // 1. Parse history.jsonl for message/session counts
        let historyURL = claudeDir.appendingPathComponent("history.jsonl")
        let (messageCount, sessionCount, sessionIds) = parseHistoryCounts(url: historyURL)

        // 2. Parse project JSONLs for token counts
        let (inputTokens, outputTokens) = parseTokenCounts(claudeDir: claudeDir, sessionIds: sessionIds)

        guard messageCount > 0 else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        return LiveDayStats(
            date: formatter.string(from: Date()),
            messageCount: messageCount,
            sessionCount: sessionCount,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }

    private static func parseHistoryCounts(url: URL) -> (messages: Int, sessions: Int, sessionIds: Set<String>) {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return (0, 0, [])
        }

        let startTimestamp = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970 * 1000
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

    private static func parseTokenCounts(claudeDir: URL, sessionIds: Set<String>) -> (input: Int, output: Int) {
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
                          let usage = entry.message?.usage else {
                        continue
                    }
                    totalInput += usage.inputTokens ?? 0
                    totalOutput += usage.outputTokens ?? 0
                }
            }
        }

        return (totalInput, totalOutput)
    }
}

