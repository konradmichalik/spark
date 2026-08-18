import Foundation

// MARK: - Persistence

enum TranscriptCachePersistence {
    static var defaultFileURL: URL {
        // swiftlint:disable:next force_unwrapping
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Spark")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("transcript-cache.json")
    }

    static func load(from url: URL = defaultFileURL) -> TranscriptCacheStore {
        guard let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(TranscriptCacheStore.self, from: data),
              store.schemaVersion == TranscriptCacheStore.currentSchemaVersion else {
            return .empty
        }
        return store
    }

    static func save(_ store: TranscriptCacheStore, to url: URL = defaultFileURL) {
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: url)
        }
    }
}

// MARK: - Concurrency-safe production entry point

/// Serializes access to the shared in-memory + on-disk cache so overlapping stats refreshes
/// (e.g. a rapid period switch while a broader-period scan is still running) can't race on it.
actor LiveTranscriptCache {
    static let shared = LiveTranscriptCache()

    private var store: TranscriptCacheStore?

    func aggregate(claudeDirs: [URL], cutoff: Date?) -> TranscriptTotals {
        var current = store ?? TranscriptCachePersistence.load()
        var combined = TranscriptTotals()

        for claudeDir in claudeDirs {
            let result = TranscriptCache.aggregate(claudeDir: claudeDir, cutoff: cutoff, store: &current)
            combined.sessionIds.formUnion(result.sessionIds)
            combined.input += result.input
            combined.output += result.output
            combined.cacheCreation += result.cacheCreation
            combined.cacheRead += result.cacheRead
            for (model, totals) in result.modelTotals {
                combined.modelTotals[model, default: ModelTokenTotals()].merge(totals)
            }
        }

        store = current
        TranscriptCachePersistence.save(current)
        return combined
    }
}
