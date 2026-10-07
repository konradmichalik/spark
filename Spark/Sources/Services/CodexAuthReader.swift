import Foundation

/// The Codex CLI's data directory: `$CODEX_HOME` if set, otherwise `~/.codex`.
enum CodexHome {
    static func resolve(environmentValue: String?, homeDirectory: URL) -> URL {
        let trimmed = environmentValue?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !trimmed.isEmpty else { return homeDirectory.appendingPathComponent(".codex") }
        if trimmed.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(trimmed.dropFirst(2)))
        }
        return URL(fileURLWithPath: trimmed)
    }

    static var current: URL {
        resolve(
            environmentValue: ProcessInfo.processInfo.environment["CODEX_HOME"],
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    static var authFile: URL { current.appendingPathComponent("auth.json") }
    static var sessionsDirectory: URL { current.appendingPathComponent("sessions") }
}

struct CodexCredentials: Sendable, Equatable {
    let accessToken: String
    let accountId: String?
}

/// Reads the ChatGPT sign-in that the Codex CLI keeps in `auth.json`. Read-only on purpose:
/// Codex rotates refresh tokens, so a refresh done by Spark would invalidate the CLI's own copy
/// and sign it out. The file is re-read on every poll instead, which picks up a token the CLI
/// refreshed in the meantime.
enum CodexAuthReader {
    static func read(from authFile: URL) -> CodexCredentials? {
        guard let data = try? Data(contentsOf: authFile),
              let file = try? JSONDecoder().decode(CodexAuthFile.self, from: data),
              let token = file.tokens?.accessToken, !token.isEmpty else {
            return nil
        }
        return CodexCredentials(accessToken: token, accountId: file.tokens?.accountId)
    }

    static func read() -> CodexCredentials? {
        read(from: CodexHome.authFile)
    }
}

/// Only the fields Spark needs. The refresh and id tokens are never decoded.
private struct CodexAuthFile: Decodable {
    let tokens: CodexAuthTokens?
}

private struct CodexAuthTokens: Decodable {
    let accessToken: String?
    let accountId: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case accountId = "account_id"
    }
}
