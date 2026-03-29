import AppKit
import Foundation

@MainActor
class OAuthService: ObservableObject {
    @Published var isAuthenticating = false
    @Published var error: String?

    var onAuthenticated: ((String) -> Void)?

    /// Try to authenticate using Claude Code Keychain credentials
    func loginViaCLI() {
        isAuthenticating = true
        error = nil

        guard let token = readTokenFromKeychain() else {
            self.error = AuthError.noToken.localizedDescription
            self.isAuthenticating = false
            return
        }

        onAuthenticated?(token)
        isAuthenticating = false
    }

    /// Open Claude Code CLI login flow in terminal
    func openCLILogin() {
        // Open Terminal and run claude auth login
        let script = """
        tell application "Terminal"
            activate
            do script "claude auth login"
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var errorInfo: NSDictionary?
            appleScript.executeAndReturnError(&errorInfo)
        }
    }

    // MARK: - CLI Helpers

    private func runCLI(args: [String]) async throws -> String {
        let claudePath = findClaudeBinary()
        guard let path = claudePath else {
            throw AuthError.cliNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func findClaudeBinary() -> String? {
        let paths = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(NSHomeDirectory())/.npm-global/bin/claude",
            "\(NSHomeDirectory())/.local/bin/claude",
        ]
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // Try which
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let result = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let result, !result.isEmpty, FileManager.default.isExecutableFile(atPath: result) {
            return result
        }
        return nil
    }

    private func readTokenFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }

        // Parse: { "claudeAiOauth": { "accessToken": "sk-ant-..." } }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else {
            return nil
        }

        return token
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case cliNotFound
    case cliNotLoggedIn
    case noToken

    var errorDescription: String? {
        switch self {
        case .cliNotFound: return "Claude Code CLI not found. Please install: brew install claude-code"
        case .cliNotLoggedIn: return "Claude Code CLI is not logged in. Please run 'claude auth login'."
        case .noToken: return "No OAuth token found in Keychain."
        }
    }
}
