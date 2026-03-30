<p align="center">
  <img src="assets/spark-logo.png" width="128" alt="Spark Logo">
</p>

# Spark

A native macOS menu bar app that shows your Claude Code usage at a glance.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Menu Bar Icon** with color-coded status (green/orange/red) showing your current usage percentage
- **Session & Weekly Usage** with progress bars and reset timers
- **Usage History Graph** showing the last 6 hours of session and weekly utilization
- **Claude Service Status** from status.claude.com — only shown when there's an active incident
- **Native Notifications** for usage warnings, critical levels, limit resets, and status incidents
- **Smart Refresh Mode** that automatically adjusts the polling interval based on usage activity (5m active, up to 30m idle)
- **Customizable Appearance** — choose between Minimal, Dot, or Claude Logo icon styles
- **Auto-connect** via Claude Code CLI credentials from your macOS Keychain

## Requirements

- macOS 14.0 (Sonoma) or later
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and logged in
- Xcode 16+ (for building from source)

## Installation

### Build from Source

```bash
git clone https://github.com/konradmichalik/spark.git
cd spark
brew install xcodegen
xcodegen generate
open Spark.xcodeproj
```

In Xcode:
1. Select your development team in **Signing & Capabilities**
2. Press **Cmd+R** to build and run

### First Launch

The app automatically detects your Claude Code CLI credentials from the macOS Keychain. If it doesn't connect automatically:

1. Click the menu bar icon
2. Open **Settings > Connection**
3. Click **Load Credentials**

If you haven't logged in to Claude Code yet:

```bash
claude auth login
```

## Usage

### Menu Bar

The menu bar shows the Claude logo (or a dot/percentage depending on your style preference) colored by your current usage level:

| Color | Meaning |
|-------|---------|
| Green | Below warning threshold (default <75%) |
| Orange | Warning level (default 75-90%) |
| Red | Critical level (default >90%) |

Click the icon to open the popover with detailed usage information.

### Settings

| Tab | Description |
|-----|-------------|
| **Connection** | Manage your Claude Code CLI authentication |
| **Appearance** | Icon style, displayed value (highest/session/weekly), Sonnet toggle |
| **General** | Refresh mode (smart/fixed), launch at login |
| **Notifications** | Warning/critical thresholds, event toggles, test notification |
| **Status** | Live status of all Claude service components |
| **About** | Version info and project link |

### Smart Refresh

The smart refresh mode adapts polling frequency based on detected usage changes:

| Tier | Interval | Condition |
|------|----------|-----------|
| Active | 5 min | Usage is changing |
| Idle | 10 min | No change for 3 cycles |
| Idle+ | 15 min | No change for 6 cycles |
| Sleep | 30 min | No change for 10+ cycles |

Returns to active mode instantly when usage changes are detected.

## How It Works

The app reads the OAuth token stored by Claude Code CLI in the macOS Keychain and queries the `api.anthropic.com/api/oauth/usage` endpoint. Service status is fetched from `status.claude.com/api/v2/summary.json`.

No browser session cookies or web scraping required.

## Project Structure

```
Spark/
  Sources/
    App/          SparkApp.swift (entry point, menu bar label)
    Models/       Models.swift (API responses, usage data, status)
    Services/     UsageClient, KeychainService
    Views/        MenuBarView, UsageGraphView, SettingsView, ClaudeLogoShape
  Assets.xcassets/
  Info.plist
  Spark.entitlements
```

## Acknowledgments

Inspired by:
- [ClaudeMeter](https://github.com/eddmann/ClaudeMeter)
- [claude-usage-bar](https://github.com/mnapoli/claude-usage-bar)
- [Claude-Usage-Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker)
- [Usage4Claude](https://github.com/f-is-h/Usage4Claude)

## License

MIT
