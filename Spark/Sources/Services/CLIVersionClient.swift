import Foundation
import os

enum CLIVersionClient {

    private static let log = Logger(subsystem: "com.konradmichalik.spark", category: "cli-version")

    // MARK: - npm Registry

    struct NpmPackage: Decodable {
        let version: String
    }

    // swiftlint:disable:next force_unwrapping
    private static let registryURL = URL(string: "https://registry.npmjs.org/@anthropic-ai/claude-code/latest")!

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

    // MARK: - Local CLI

    static func readLocalVersion() async -> String? {
        await Task.detached {
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["claude", "--version"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8) else { return nil }

                return output
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: " ")
                    .first
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
