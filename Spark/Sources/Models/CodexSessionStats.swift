import Foundation

/// Local Codex usage, read from the CLI's rollout files (`$CODEX_HOME/sessions/YYYY/MM/DD/rollout-*.jsonl`
/// and `archived_sessions/`).
///
/// `token_count` events carry the thread's *cumulative* `total_token_usage`, and the CLI
/// re-emits them unchanged when only the rate limits move. So tokens are counted as the delta
/// between consecutive totals, each attributed to the timestamp of the event it came from: a
/// re-emitted event adds nothing, and a session resumed today contributes only today's turns.
struct CodexSessionStats: Equatable, Sendable {
    var sessionCount = 0
    var messageCount = 0
    /// Fresh input only. Codex's `input_tokens` includes the cached part, which is split out here.
    var inputTokens = 0
    var cachedInputTokens = 0
    /// Includes `reasoningTokens`, which OpenAI bills as output.
    var outputTokens = 0
    var reasoningTokens = 0
    var modelTokens: [String: Int] = [:]
    /// Rollout files found at all, regardless of period. Zero means Codex never ran locally.
    var fileCount = 0

    var totalTokens: Int { inputTokens + cachedInputTokens + outputTokens }

    static func parse(directories: [URL], since: Date?) -> CodexSessionStats {
        var result = CodexSessionStats()
        for file in directories.flatMap(rolloutFiles) {
            result.fileCount += 1
            // A file untouched since the cutoff cannot hold activity inside the period.
            if let since, let modified = modificationDate(of: file), modified < since { continue }
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            result.add(parseFile(content: content, since: since))
        }
        return result
    }

    static func parseFile(content: String, since: Date?) -> CodexSessionStats {
        var accumulator = RolloutAccumulator(since: since)
        content.enumerateLines { line, _ in accumulator.consume(line) }
        return accumulator.stats
    }

    private mutating func add(_ other: CodexSessionStats) {
        sessionCount += other.sessionCount
        messageCount += other.messageCount
        inputTokens += other.inputTokens
        cachedInputTokens += other.cachedInputTokens
        outputTokens += other.outputTokens
        reasoningTokens += other.reasoningTokens
        modelTokens.merge(other.modelTokens, uniquingKeysWith: +)
    }

    private static func rolloutFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        // `.jsonl.zst` (compressed old rollouts, behind a Codex feature flag) is skipped: Apple's
        // frameworks have no zstd decoder.
        return enumerator.compactMap { $0 as? URL }.filter {
            $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl"
        }
    }

    private static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

/// Walks one rollout file line by line, keeping the last cumulative totals and current model.
private struct RolloutAccumulator {
    let since: Date?
    var stats = CodexSessionStats()
    private var previous = RolloutTokenUsage()
    private var model: String?
    private var hasActivity = false

    init(since: Date?) {
        self.since = since
    }

    mutating func consume(_ line: String) {
        // Most lines are model output or tool calls. Skip them before paying for JSON decoding.
        guard line.contains("\"token_count\"") || line.contains("\"user_message\"") || line.contains("\"turn_context\"")
        else { return }
        guard let entry = try? JSONDecoder().decode(RolloutLine.self, from: Data(line.utf8)) else { return }

        switch (entry.type, entry.payload?.type) {
        case ("turn_context", _):
            model = entry.payload?.model ?? model
        case ("event_msg", "user_message"):
            guard isInPeriod(entry.timestamp) else { return }
            stats.messageCount += 1
            markActive()
        case ("event_msg", "token_count"):
            guard let total = entry.payload?.info?.totalTokenUsage else { return }
            countDelta(to: total, inPeriod: isInPeriod(entry.timestamp))
        default:
            return
        }
    }

    private mutating func countDelta(to total: RolloutTokenUsage, inPeriod: Bool) {
        defer { previous = total }
        // A lower total means a different counter (e.g. after a fork). Restart from it.
        guard total.input >= previous.input, total.output >= previous.output, inPeriod else { return }
        let cached = max(total.cached - previous.cached, 0)
        let input = total.input - previous.input
        let output = total.output - previous.output
        guard input > 0 || output > 0 else { return }

        stats.inputTokens += max(input - cached, 0)
        stats.cachedInputTokens += cached
        stats.outputTokens += output
        stats.reasoningTokens += max(total.reasoning - previous.reasoning, 0)
        stats.modelTokens[model ?? "unknown", default: 0] += input + output
        markActive()
    }

    private mutating func markActive() {
        guard !hasActivity else { return }
        hasActivity = true
        stats.sessionCount = 1
    }

    /// Lines without a parsable timestamp only count when there is no cutoff.
    private func isInPeriod(_ timestamp: String?) -> Bool {
        guard let since else { return true }
        guard let date = timestamp.flatMap(Self.parseDate) else { return false }
        return date >= since
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

private struct RolloutLine: Decodable {
    let timestamp: String?
    let type: String
    let payload: RolloutPayload?
}

private struct RolloutPayload: Decodable {
    let type: String?
    let model: String?
    let info: RolloutTokenInfo?
}

private struct RolloutTokenInfo: Decodable {
    let totalTokenUsage: RolloutTokenUsage?

    enum CodingKeys: String, CodingKey {
        case totalTokenUsage = "total_token_usage"
    }
}

private struct RolloutTokenUsage: Decodable {
    var input = 0
    var cached = 0
    var output = 0
    var reasoning = 0

    enum CodingKeys: String, CodingKey {
        case input = "input_tokens"
        case cached = "cached_input_tokens"
        case output = "output_tokens"
        case reasoning = "reasoning_output_tokens"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = try container.decodeIfPresent(Int.self, forKey: .input) ?? 0
        cached = try container.decodeIfPresent(Int.self, forKey: .cached) ?? 0
        output = try container.decodeIfPresent(Int.self, forKey: .output) ?? 0
        reasoning = try container.decodeIfPresent(Int.self, forKey: .reasoning) ?? 0
    }
}
