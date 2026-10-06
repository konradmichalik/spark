# AGENTS.md

## Project overview

Spark is a native macOS menu bar app (SwiftUI, Swift 6) that displays Claude Code usage metrics. It reads the OAuth token from the macOS Keychain, fetches usage from `api.anthropic.com/api/oauth/usage` and shows a fill-ring icon with the percentage in the menu bar. Requires macOS 14+ and Xcode 16+. The repository is `konradmichalik/spark`.

## Structure

- `Spark/Sources/App/`: app entry (`SparkApp.swift`)
- `Spark/Sources/Models/`: `AppState` (`@MainActor`, `@Observable`, single source of truth), usage and stats models, transcript caches, persistence
- `Spark/Sources/Services/`: `KeychainService`, `UsageClient`, `CLIVersionClient`, `TranscriptFileWatcher`, `SparkCredentialStore`
- `Spark/Sources/Views/`: `MenuBarView` (main popover), usage graphs, `SettingsView`, `WeeklyReportView`, `Views/Components/` (`SectionHeader`, `SectionCard`, `SegmentPicker`, `TablerIcon`)
- `Spark/Assets.xcassets/Icons/`: bundled Tabler outline SVG icon set
- `SparkTests/`: unit tests
- `project.yml`: XcodeGen project definition, the source of truth for project config
- `scripts/fetch-tabler-icons.sh`: downloads Tabler icons
- `site/`: landing page, `docs/`: how-it-works, usage and release docs
- `.githooks/pre-commit`: SwiftLint on staged Swift files

Data flow: timer-based polling, `UsageClient` fetches the API, `AppState` updates, SwiftUI re-renders. Backoff runs from 5 minutes (active) to 30 minutes (idle) and snaps back on usage change. Local stats come from `~/.claude/history.jsonl` and per-project JSONL files. Active sessions are sessions with a transcript write in the last 5 minutes.

## Development commands

```bash
make setup    # brew install xcodegen swiftlint, set core.hooksPath to .githooks (first time only)
make xcode    # generate Spark.xcodeproj from project.yml
make build    # release build (runs xcodegen first)
make clean    # remove build artifacts and the generated .xcodeproj
```

- `Spark.xcodeproj` is generated and git-ignored: run `make xcode` after cloning and after adding or removing files, never edit it by hand
- To add an icon: add the case to the `TablerIcon` enum, add the raw Tabler asset name (for example `adjustments-horizontal`, not the Swift case name) to the `ICONS` array in `scripts/fetch-tabler-icons.sh`, run the script, then `make xcode`. A missed step fails `TablerIconTests`

## Testing

```bash
xcodebuild -scheme Spark -configuration Debug test
```

CI (`build.yml`, macos-15) generates the project with XcodeGen, then runs a Release build and the Debug tests with `CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO`.

## Code style and linting

```bash
make lint     # swiftlint lint --strict
```

- SwiftLint config in `.swiftlint.yml`: line length 150 warning and 200 error, function bodies 50 lines warning, files 400 lines warning
- CI runs `swiftlint lint --strict` in `lint.yml`
- Swift 6 strict concurrency: `@MainActor` for UI, `Task.detached` for background network calls
- No external dependencies, only Apple frameworks (SwiftUI, Combine, AppKit, Security, UserNotifications)
- User preferences persist via `@AppStorage`

## Git workflow

- Commit format: `<type>: <description>`, with type one of feat, fix, refactor, docs, test, chore, perf, ci
- Release notes are generated from commit prefixes between tags
- One commit per logical change, no co-author trailers
- Open an issue first for anything beyond a small fix. A pull request merges once lint and build/test are green
- Release: update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, tag `v1.x.x`, push the tag. GitHub Actions builds the dual-arch DMGs and updates the Homebrew tap
