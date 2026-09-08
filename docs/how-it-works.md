# How Spark works

Spark queries `api.anthropic.com/api/oauth/usage` using the OAuth token Claude Code CLI stores in the macOS Keychain via `KeychainService`. Account tier info (Pro, Max, Team, etc.) is read from the same Keychain entry. Service status is fetched from `status.anthropic.com/api/v2/summary.json`. All network calls run on a background actor; the UI updates on the main thread via `@Observable` state.

> [!WARNING]
> Spark relies on an undocumented internal API endpoint. Anthropic may change or remove it without notice. If data stops loading after a CLI update, check for a new Spark release.

## Project structure

```text
Spark/Sources/
  App/        SparkApp.swift — entry point, menu bar controller
  Models/     Models.swift, AppState.swift, StatsModels.swift, Theme.swift
  Services/   UsageClient.swift, KeychainService.swift
  Views/      MenuBarView, UsageGraphView, SettingsView, ClaudeLogoShape
  Views/Components/  SectionHeader, SectionCard, SegmentPicker, TablerIcon — shared across the
              popover and settings window
```

> [!NOTE]
> The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`) so the `.xcodeproj` is fully derived — never edit it by hand.

## Adding an icon

Icons are bundled Tabler outline SVGs (`Spark/Assets.xcassets/Icons/`), wrapped by the `TablerIcon` enum and rendered with `TablerIconView`. To add one: add the enum case in `TablerIcon.swift`, add the same name to the `ICONS` array in `scripts/fetch-tabler-icons.sh`, re-run the script, then `make xcode`. `ICONS` takes the raw Tabler asset name (`adjustments-horizontal`), not the Swift case name (`adjustmentsHorizontal`) — the script builds both the download URL and the image-set directory name from that string, so a camel-cased entry downloads nothing and generates an asset no case can find. Skip a step and `TablerIconTests` goes red — either the new case has no asset, or (running the script without adding a case) a stale `.imageset` ships with nothing pointing at it.
