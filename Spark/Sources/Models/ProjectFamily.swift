import Foundation

/// Resolves a readable name for a project directory key from `~/.claude/projects/`.
enum ProjectFamily {
    /// `cwd`, when known, is authoritative — only its last path component is shown, since a full
    /// absolute path doesn't fit a popover row. Falls back to the last non-empty segment of the
    /// path-encoded directory name itself (e.g. `-Users-konrad-dev-typo3-routing` -> `routing`) —
    /// lossy (a hyphen in the original path component is indistinguishable from a path separator)
    /// but readable, and never ambiguous as a *key*: callers always key by `key`, never by this
    /// display string, so two projects whose display names coincide remain distinct entries.
    static func displayName(forKey key: String, cwd: String?) -> String {
        if let cwd, !cwd.isEmpty {
            return URL(fileURLWithPath: cwd).lastPathComponent
        }
        return key.split(separator: "-").last.map(String.init) ?? key
    }
}
