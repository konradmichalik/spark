# How Spark works

Spark queries `api.anthropic.com/api/oauth/usage` using the OAuth token Claude Code CLI stores in the macOS Keychain via `KeychainService`. Account tier info (Pro, Max, Team, etc.) is read from the same Keychain entry. Service status is fetched from `status.anthropic.com/api/v2/summary.json`. With "API Cost Estimate" enabled, the public Claude prices are downloaded from the LiteLLM price list on `raw.githubusercontent.com` at most once a day and cached in `pricing.json`. Only the request itself leaves the Mac, no usage data is sent. All network calls run on a background actor; the UI updates on the main thread via `@Observable` state.

> [!WARNING]
> Spark relies on an undocumented internal API endpoint. Anthropic may change or remove it without notice. If data stops loading after a CLI update, check for a new Spark release.

## Codex

`CodexState` runs next to `AppState` and stays inert until `CodexAuthReader` finds a ChatGPT sign-in in `$CODEX_HOME/auth.json` (default `~/.codex`). It then polls `chatgpt.com/backend-api/wham/usage`, the endpoint the Codex CLI uses for `/status`, every 5 minutes. The file is re-read before every poll and never written: Codex rotates refresh tokens, so a refresh by Spark would sign the CLI out. A 401 triggers one re-read and retry, then a "run `codex login`" prompt.

Codex windows are classified by length, not by position: up to 6 hours is the session window, 6 to 8 days the weekly one, anything else (the Free plan's 30-day window, per-model limits) gets its own row. `CodexUsage` maps them onto the existing `UsageData`, so the Claude rows and rings render them unchanged.

Local stats come from the rollout files in `sessions/` and `archived_sessions/`. `token_count` events hold cumulative totals, so `CodexSessionStats` counts the delta between consecutive events at each event's timestamp. `input_tokens` includes cached tokens, which are split out.

> [!WARNING]
> The Codex usage endpoint is undocumented as well and has changed shape before. Decoding is lenient: unknown fields are ignored and missing windows are hidden.

## Project structure

```text
Spark/Sources/
  App/        SparkApp.swift — entry point, menu bar controller
  Models/     Models.swift, AppState.swift, StatsModels.swift, Theme.swift,
              CodexState.swift, CodexUsage.swift, CodexSessionStats.swift, MenuBarReading.swift
  Services/   UsageClient.swift, KeychainService.swift, CodexAuthReader.swift, CodexUsageClient.swift
  Views/      MenuBarView, SettingsView, WeeklyReportView, ClaudeLogoShape
  Views/Popover/     PopoverHeader, the overview and the detail screens (History, Active Sessions,
              Statistics, All Limits, Not connected)
  Views/Components/  DotBar, DotRing, PaperSegments, Tooltip, TablerIcon and the settings
              controls (SectionHeader, SectionCard, SegmentPicker)
```

> [!NOTE]
> The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`) so the `.xcodeproj` is fully derived — never edit it by hand.

## Adding an icon

Icons are bundled Tabler outline SVGs (`Spark/Assets.xcassets/Icons/`), wrapped by the `TablerIcon` enum and rendered with `TablerIconView`. To add one: add the enum case in `TablerIcon.swift`, add the same name to the `ICONS` array in `scripts/fetch-tabler-icons.sh`, re-run the script, then `make xcode`. `ICONS` takes the raw Tabler asset name (`adjustments-horizontal`), not the Swift case name (`adjustmentsHorizontal`) — the script builds both the download URL and the image-set directory name from that string, so a camel-cased entry downloads nothing and generates an asset no case can find. Skip a step and `TablerIconTests` goes red — either the new case has no asset, or (running the script without adding a case) a stale `.imageset` ships with nothing pointing at it.
