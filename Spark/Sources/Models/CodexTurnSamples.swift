import Foundation

/// Recent fresh-token deltas from local Codex CLI rollout files. This scan is independent from
/// statistics-period parsing so a visit to the `.all` statistics screen cannot widen its work.
enum CodexTurnSamples {
    static func parse(directories: [URL], cutoff: Date, now: Date) -> [TurnSample] {
        directories.flatMap(CodexSessionStats.rolloutFiles)
            .filter { (CodexSessionStats.modificationDate(of: $0) ?? .distantPast) >= cutoff }
            .flatMap { url -> [TurnSample] in
                guard !Task.isCancelled, let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
                return parseFile(content: content, cutoff: cutoff, now: now)
            }
            .sorted { $0.date < $1.date }
    }

    /// Earlier events are still read to establish the cumulative baseline for the first event
    /// in-window. Only positive fresh-input-plus-output deltas are retained.
    static func parseFile(content: String, cutoff: Date, now: Date) -> [TurnSample] {
        var accumulator = TurnAccumulator(cutoff: cutoff, now: now)
        content.enumerateLines { line, _ in accumulator.consume(line) }
        return accumulator.samples
    }
}

private struct TurnAccumulator {
    let cutoff: Date
    let now: Date
    private let decoder = JSONDecoder()
    private(set) var samples: [TurnSample] = []
    private var previous = RolloutTokenUsage()

    init(cutoff: Date, now: Date) {
        self.cutoff = cutoff
        self.now = now
    }

    mutating func consume(_ line: String) {
        guard line.contains("\"token_count\"") else { return }
        guard let entry = try? decoder.decode(RolloutLine.self, from: Data(line.utf8)),
              entry.type == "event_msg", entry.payload?.type == "token_count",
              let total = entry.payload?.info?.totalTokenUsage else { return }

        let timestamp = entry.timestamp.flatMap(CodexSessionStats.parseDate)
        if total.input < previous.input || total.output < previous.output { previous = RolloutTokenUsage() }
        let freshInputDelta = max(total.input - previous.input - max(total.cached - previous.cached, 0), 0)
        let outputDelta = max(total.output - previous.output, 0)
        previous = total

        guard let timestamp, timestamp >= cutoff, timestamp <= now, freshInputDelta + outputDelta > 0 else { return }
        samples.append(TurnSample(date: timestamp, tokens: freshInputDelta + outputDelta))
    }
}
