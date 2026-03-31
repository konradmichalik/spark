# Development

## How It Works

Spark queries `api.anthropic.com/api/oauth/usage` using the OAuth token Claude Code CLI stores in the macOS Keychain via `KeychainService`. Account tier info (Pro, Max, Team, etc.) is read from the same Keychain entry. Service status is fetched from `status.anthropic.com/api/v2/summary.json`. All network calls run on a background actor; the UI updates on the main thread via `@Observable` state.

> [!WARNING]
> Spark relies on an undocumented internal API endpoint. Anthropic may change or remove it without notice. If data stops loading after a CLI update, check for a new Spark release.

## Project Structure

```
Spark/Sources/
  App/        SparkApp.swift — entry point, menu bar controller
  Models/     Models.swift, AppState.swift, StatsModels.swift, Theme.swift
  Services/   UsageClient.swift, KeychainService.swift
  Views/      MenuBarView, UsageGraphView, SettingsView, ClaudeLogoShape
```

> [!NOTE]
> The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`) so the `.xcodeproj` is fully derived — never edit it by hand.

## Prerequisites

- macOS 14.0 (Sonoma) or later
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- [SwiftLint](https://github.com/realm/SwiftLint) (`brew install swiftlint`)

## Setup

```bash
git clone https://github.com/konradmichalik/spark.git
cd spark
make setup    # Installs XcodeGen, SwiftLint, configures git hooks
make xcode    # Generates Spark.xcodeproj
open Spark.xcodeproj
```

## Build & Test

```bash
make build    # Release build
make lint     # SwiftLint (strict mode)
```

Or in Xcode: select your development team under **Signing & Capabilities**, then **Cmd+R**.

## Contributing

Pull requests are welcome. For larger changes, open an issue first to discuss the approach.

> [!IMPORTANT]
> Do not commit the generated `.xcodeproj` contents — only `project.yml` is the source of truth for project configuration.

## Release

Releases are automated via GitHub Actions. To create a new release:

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`
2. Commit and tag:
   ```bash
   git tag v1.x.x
   git push --tags
   ```
3. GitHub Actions builds dual-arch DMGs (arm64 + x86_64), creates a GitHub Release, and updates the Homebrew tap automatically.
