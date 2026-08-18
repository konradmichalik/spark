import Foundation

/// Resolves the Claude Code config directory (or directories). Checked in priority order:
///
/// 1. `CLAUDE_CONFIG_DIR`, if set — treated as a comma-separated list, a convention borrowed
///    from `ccusage` rather than documented Claude Code behaviour, so it's supported
///    defensively without being presented as the primary format.
/// 2. `~/.claude`
/// 3. `~/.config/claude`
///
/// Every candidate that exists is returned, deduplicated after symlink resolution so a
/// symlinked setup isn't scanned twice.
enum ClaudeConfigDirectory {
    struct Resolution: Equatable {
        let roots: [URL]

        /// Shown in Settings so a user seeing zero stats can diagnose which root was used.
        var primary: URL? { roots.first }
    }

    static func resolve(
        environmentValue: String?,
        homeDirectory: URL,
        directoryExists: (URL) -> Bool = { url in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return exists && isDirectory.boolValue
        }
    ) -> Resolution {
        var candidates: [URL] = []
        if let environmentValue {
            candidates += environmentValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { URL(fileURLWithPath: $0) }
        }
        candidates.append(homeDirectory.appendingPathComponent(".claude"))
        candidates.append(homeDirectory.appendingPathComponent(".config/claude"))

        var seenResolvedPaths: Set<String> = []
        var roots: [URL] = []
        for candidate in candidates where directoryExists(candidate) {
            let resolvedURL = candidate.resolvingSymlinksInPath()
            guard seenResolvedPaths.insert(resolvedURL.path).inserted else { continue }
            roots.append(resolvedURL)
        }
        return Resolution(roots: roots)
    }

    /// Convenience for production call sites — resolves against the real environment and home directory.
    static func resolveCurrent() -> Resolution {
        resolve(
            environmentValue: ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"],
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }
}
