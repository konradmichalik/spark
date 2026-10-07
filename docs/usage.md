# Usage

## Menu bar icon

The icon reflects your highest current usage level:

| Color | Meaning |
|-------|---------|
| Green | Below warning threshold (default < 75%) |
| Orange | Warning level (default 75–90%) |
| Red | Critical level (default > 90%) |

Click the icon to open the detailed popover with usage stats, the history graph, and service status. The icon style (Minimal, Dot, or Logo; colored or monochrome) is set in **Settings → Menu Bar**.

## Claude and Codex

With a Codex ChatGPT sign-in present, the popover gets a **Claude | Codex** switch and **Settings → Menu Bar → Provider** decides what the icon reports:

| Provider | Menu bar shows |
|----------|----------------|
| Highest (default) | Whichever of Claude and Codex is closer to its limit |
| Claude | Claude only |
| Codex | Codex only |
| Both | `Claude% \| Codex%`, ring and color follow the higher one |

Each tab also shows that provider's session usage, colored from the warning threshold up, so both can be read without switching. Turn it off under **Settings → Display → Session Usage in Provider Tabs**.

If a Codex plan lacks the window picked under **Displayed Value** (Pro has no 5-hour window, Free only a 30-day one), Spark uses that plan's highest window instead of showing 0%.

## Smart refresh

| Tier | Interval | Trigger |
|------|----------|---------|
| Active | 5 min | Usage is changing |
| Idle | 10 min | No change for 3 cycles |
| Idle+ | 15 min | No change for 6 cycles |
| Sleep | 30 min | No change for 11+ cycles |

> [!TIP]
> Smart refresh drops back to **Active** instantly the moment it detects a change — either in your reported usage percentage, or in your local Claude Code transcripts, which Spark watches directly. Local activity is the faster signal in practice: it fires the moment you start a new message, not just when the next poll happens to notice a changed percentage.

## Data export

**Settings → General → Data Export → Export data for external apps** (off by default) writes the current usage state to `~/Library/Application Support/Spark/data.json` on every refresh, for external consumers such as a Stream Deck plugin. Turning it off deletes the file.
