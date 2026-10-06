import Foundation
import os

struct PricingCache: Codable, Equatable, Sendable {
    let fetchedAt: Date
    let table: PricingTable
}

enum PricingClient {

    private static let log = Logger(subsystem: "com.konradmichalik.spark", category: "pricing")

    private static let sourceURL = URL(
        string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
    )!

    private static let maxCacheAge: TimeInterval = 24 * 60 * 60

    static var defaultCacheURL: URL {
        AppSupportDirectory.spark.appendingPathComponent("pricing.json")
    }

    /// The cached table while it is younger than a day, otherwise a fresh download. A failed
    /// download falls back to the stale cache, so a missing network never removes the costs.
    static func currentTable(
        now: Date = Date(),
        cacheURL: URL = defaultCacheURL,
        fetch: @Sendable () async throws -> PricingTable = fetchTable
    ) async -> PricingTable? {
        let cached = loadCache(from: cacheURL)
        if let cached, now.timeIntervalSince(cached.fetchedAt) < maxCacheAge {
            return cached.table
        }
        do {
            let table = try await fetch()
            saveCache(PricingCache(fetchedAt: now, table: table), to: cacheURL)
            return table
        } catch {
            log.error("Failed to fetch prices: \(error.localizedDescription, privacy: .public)")
            return cached?.table
        }
    }

    static func fetchTable() async throws -> PricingTable {
        var request = URLRequest(url: sourceURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try PricingTable.parse(data)
    }

    static func loadCache(from url: URL) -> PricingCache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PricingCache.self, from: data)
    }

    static func saveCache(_ cache: PricingCache, to url: URL) {
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: url)
        }
    }
}
