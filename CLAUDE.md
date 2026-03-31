# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Spark is a native macOS menu bar app (SwiftUI, Swift 6) that displays Claude Code usage metrics. It reads the OAuth token from macOS Keychain, fetches usage from `api.anthropic.com/api/oauth/usage`, and shows a fill-ring icon with percentage in the menu bar. Requires macOS 14+, Xcode 16+.

## Build & Lint

```bash
make setup    # Install XcodeGen + SwiftLint, configure git hooks (first time only)
make xcode    # Generate Spark.xcodeproj from project.yml
make build    # Release build (runs xcodegen first)
make lint     # SwiftLint strict mode
make clean    # Remove build artifacts + .xcodeproj
```

Run tests via Xcode or:
```bash
xcodebuild -scheme Spark -configuration Debug test
```

## Architecture

**State:** `AppState` (`@MainActor`, `@Observable`) is the single source of truth. Views read published properties; all mutations happen through AppState methods. User preferences persist via `@AppStorage`.

**Data flow:** Timer-based polling → `UsageClient` fetches API → `AppState` updates → SwiftUI re-renders. Smart backoff: 5min (active) → 30min (idle), snaps back on usage change.

**Services:**
- `KeychainService` — reads/writes OAuth tokens from macOS Keychain (`com.konradmichalik.spark` service + Claude Code's stored credentials)
- `UsageClient` — async HTTP client for usage API and status page

**Views:** `MenuBarExtra` scene → `MenuBarView` (main popover) → child views (`UsageGraphView`, `SettingsView`, `ClaudeLogoShape` for the ring icon)

**Local stats:** Parses `~/.claude/history.jsonl` and per-project JSONL files for daily message/token counts.

## Key Conventions

- `project.yml` is the source of truth for project config — never edit `.xcodeproj` directly, never commit it
- Swift 6 strict concurrency: `@MainActor` for UI, `Task.detached` for background network calls
- SwiftLint strict mode: 150-char line warning, 200 error; function bodies ≤50 lines; files ≤400 lines warning
- No external dependencies — pure Apple frameworks only (SwiftUI, Combine, AppKit, Security, UserNotifications)

## Release

Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, tag with `v1.x.x`, push tag. GitHub Actions builds dual-arch DMGs and updates the Homebrew tap.
