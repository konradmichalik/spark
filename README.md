<div align="center">

<img src="assets/spark-logo.png" width="128" alt="">

# Spark

A native macOS menu bar app that shows your Claude Code usage at a glance, color-coded, always visible, zero friction.<br>
Learn more at <a href="https://konradmichalik.github.io/spark/">konradmichalik.github.io/spark</a>

<p>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6.0-orange" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

<img src="screenshot.jpg" width="400" alt="Spark: Claude Code usage popover showing session and weekly usage, today's stats, and a usage history graph">

</div>

---

## ✨ Features

- **Usage ring** in the menu bar that fills based on current usage: ring color shifts green → orange → red as you approach your limit
- **Account tier badge** showing your plan (Pro, Max, Team, etc.) directly in the popover header
- **Session, Weekly, Sonnet, Opus & Fable usage** with progress bars, countdown timers to the next reset, a six-tier color-coded pace marker (Comfortable → Runaway) showing whether you're tracking ahead of or behind an even-pace budget, and a pay-as-you-go extra-usage line when you exceed plan limits
- **Session projection** that estimates whether you'll hit the limit before the reset window closes, plus a live **burn rate** (fresh tokens per minute over the last 15 minutes, read from your local transcripts) that reacts before the next API poll
- **Usage history graph** with two modes: **Limits** (time-proportional utilization line chart, selectable 1h–30d) and **Volume** (daily token bar chart from permanent history, 7d/30d), both with hover tooltips
- **Stats for any period** (Today / 7d / 30d / All): message count, session count, token totals, local per-model (Sonnet/Opus/Fable) attribution, and a collapsible **Top Projects** breakdown by token volume, plus the optional API cost estimate for the period and per project
- **Active Sessions**: see which Claude Code sessions have had activity in the last 5 minutes, by project
- **Usage Report** window, switchable between week and calendar-month view and navigable back one period at a time: token total with trend vs. the period before, a Sonnet/Opus/Fable donut chart, prompt cache hit rate, a Session/Weekly pace graph with day ticks and hover detail, top projects for the period, and an optional estimate of what the period would have cost at API prices (off by default, see Settings)
- **Claude service status** pulled from `status.anthropic.com`, surfacing only when there's an active incident
- **Native notifications** for warning thresholds, critical levels, limit resets, and service incidents
- **Smart refresh** that reacts to your actual Claude Code activity: watches your transcripts directly and snaps back to active polling the moment you start working, instead of waiting for the next scheduled check
- **Customizable icon**: Minimal, Dot, or Logo style; colored or monochrome
- **Auto-connect** via Claude Code CLI credentials from macOS Keychain
- **Data export** _(opt-in)_: write live usage state to a local JSON file for external consumers such as a Stream Deck plugin, enabled in **Settings → General**

## 🔥 Installation

### Homebrew

<a href="https://github.com/konradmichalik/homebrew-tap"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fkonradmichalik.github.io%2Fhomebrew-tap%2Fbadges%2Fspark-version.json&style=flat-square&logo=homebrew" alt="Homebrew version"></a>
<a href="https://github.com/konradmichalik/homebrew-tap"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fkonradmichalik.github.io%2Fhomebrew-tap%2Fbadges%2Fspark-downloads.json&style=flat-square&logo=homebrew" alt="Homebrew downloads"></a>

```bash
brew tap konradmichalik/tap
brew install spark
```

### Update

```bash
brew upgrade --cask konradmichalik/tap/spark
```

### Requirements

- macOS 14.0 (Sonoma) or later
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated

## ⚙️ Configuration

Spark auto-detects your Claude Code credentials on first launch. If the connection doesn't happen automatically:

1. Click the menu bar icon to open the popover
1. Go to **Settings → Connection**
1. Click **Load Credentials**

If you haven't authenticated with Claude Code yet:

```bash
claude auth login
```

> [!TIP]
> After a successful `claude auth login`, Spark picks up the credentials automatically on the next refresh. No restart needed.

<!-- -->

> [!NOTE]
> Spark reads the OAuth token stored by Claude Code CLI in the macOS Keychain: no browser session cookies, no web scraping, no extra setup beyond a working `claude auth login`. On first launch, macOS asks for your login password to grant Spark access to it; this is a one-time prompt, and Spark remembers the permission afterward.

## 🐛 Troubleshooting

**No data / "Not connected" state**
Run `claude auth login` to ensure valid credentials exist, then use **Settings → Connection → Load Credentials**.

**Usage figures look stale**
Check the refresh mode in **Settings → General**. In Smart mode, the interval can stretch to 30 min during idle periods. Switch to a fixed interval if you need more frequent updates.

## 🧑‍💻 Contributing

Please have a look at [`CONTRIBUTING.md`](CONTRIBUTING.md).

## 💎 Credits

Icons by [Tabler Icons](https://tabler.io/icons), licensed under the MIT License.

## ⭐ License

This project is licensed under [MIT](LICENSE).
