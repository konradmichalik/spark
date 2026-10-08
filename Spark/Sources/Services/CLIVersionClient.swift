import Foundation
import os

enum CLIVersionClient {

    private static let log = Logger(subsystem: "com.konradmichalik.spark", category: "cli-version")

    // MARK: - npm Registry

    struct NpmPackage: Decodable {
        let version: String
    }

    private static let registryURL = URL(staticString: "https://registry.npmjs.org/@anthropic-ai/claude-code/latest")

    static func fetchLatestVersion() async throws -> String {
        var request = URLRequest(url: registryURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let package = try JSONDecoder().decode(NpmPackage.self, from: data)
        return package.version
    }

    // MARK: - Homebrew Cask API

    struct BrewCask: Decodable {
        let version: String
    }

    private static let brewCaskURL = URL(staticString: "https://formulae.brew.sh/api/cask/claude-code.json")

    static func fetchLatestVersion(for method: ClaudeCodeInstallMethod) async throws -> String {
        switch method {
        case .homebrew:
            var request = URLRequest(url: brewCaskURL)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let cask = try JSONDecoder().decode(BrewCask.self, from: data)
            return normalizedBrewVersion(cask.version)
        case .npmGlobal, .other:
            return try await fetchLatestVersion()
        }
    }

    /// Homebrew cask `version` fields sometimes use a `"<version>,<build>"` convention
    /// for casks with a secondary version component. Strip anything from the comma
    /// onward so `isNewer`'s numeric split doesn't silently corrupt on the build suffix.
    static func normalizedBrewVersion(_ raw: String) -> String {
        String(raw.split(separator: ",", maxSplits: 1).first ?? Substring(raw))
    }

    // MARK: - Install Method Detection

    static func detectInstallMethod() async -> ClaudeCodeInstallMethod {
        await Task.detached {
            let url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude.json")
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let raw = json["installMethod"] as? String else {
                return ClaudeCodeInstallMethod(rawConfigValue: nil)
            }
            return ClaudeCodeInstallMethod(rawConfigValue: raw)
        }.value
    }

    // MARK: - Local CLI

    /// The first word that starts with a digit: "2.1.294 (Claude Code)" and "codex-cli 0.46.0"
    /// both name their version that way.
    static func parseVersion(_ output: String) -> String? {
        output
            .split(whereSeparator: { $0.isWhitespace })
            .first { $0.first?.isNumber == true }
            .map(String.init)
    }

    /// Runs `<command> --version` in a login shell, since a menu bar app has a minimal PATH.
    static func readLocalVersion(command: String = "claude") async -> String? {
        await Task.detached {
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", "\(command) --version"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return String(data: data, encoding: .utf8).flatMap(parseVersion)
            } catch {
                log.error("Failed to read local CLI version: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }.value
    }

    // MARK: - Comparison

    static func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }

        for index in 0..<max(remoteParts.count, localParts.count) {
            let remoteComponent = index < remoteParts.count ? remoteParts[index] : 0
            let localComponent = index < localParts.count ? localParts[index] : 0
            if remoteComponent > localComponent { return true }
            if remoteComponent < localComponent { return false }
        }
        return false
    }
}
