import Foundation

/// The first day Codex has local activity, found from folder and file names alone so the report
/// can enable "previous period" without scanning any rollout.
enum CodexEarliestDay {
    /// `directories` are the sessions tree (`YYYY/MM/DD/rollout-*.jsonl`) and the flat
    /// `archived_sessions` folder (`rollout-YYYY-MM-DDT...jsonl`). Returns a day key like `2026-08-14`.
    static func dayKey(in directories: [URL]) -> String? {
        directories.compactMap(earliest).min()
    }

    private static func earliest(in directory: URL) -> String? {
        let fileManager = FileManager.default
        guard let years = numbered(in: directory, digits: 4) else { return nil }
        for year in years {
            for month in numbered(in: directory.appendingPathComponent(year), digits: 2) ?? [] {
                let monthDirectory = directory.appendingPathComponent(year).appendingPathComponent(month)
                for day in numbered(in: monthDirectory, digits: 2) ?? [] {
                    let dayDirectory = monthDirectory.appendingPathComponent(day)
                    if (try? fileManager.contentsOfDirectory(atPath: dayDirectory.path))?.isEmpty == false {
                        return "\(year)-\(month)-\(day)"
                    }
                }
            }
        }
        return archivedDay(in: directory)
    }

    private static func numbered(in directory: URL, digits: Int) -> [String]? {
        let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        return names?.filter { $0.count == digits && $0.allSatisfy(\.isNumber) }.sorted()
    }

    private static func archivedDay(in directory: URL) -> String? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { name -> String? in
            guard name.hasPrefix("rollout-"), name.count >= 18 else { return nil }
            let day = String(name.dropFirst(8).prefix(10))
            let parts = day.split(separator: "-")
            return parts.count == 3 && parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) ? day : nil
        }.min()
    }
}
