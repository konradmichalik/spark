# Usage

## Menu bar icon

The icon is a ring of twelve dots. Each dot stands for a twelfth of the limit, and the last one fills partially, so 45% and 50% look different. It follows the menu bar's colors until a value crosses a threshold:

| State | Icon |
|-------|------|
| Below the warning threshold (default 75%) | Menu bar color |
| Warning (default 75% to 90%) | Ochre |
| Critical (default 90% and above) | Red |
| Disconnected, sign-in expired, last fetch failed, or no update for an hour | Dimmed |

Click the icon to open the detailed popover with usage stats, the history graph, and service status. **Settings → Menu Bar** sets the style (Ring, or With logo, which puts the provider logo in front of the ring) and the value next to it.

## Popover

The popover opens on an overview of the selected provider:

- **Session**: the current value, a dot bar with the forecast (hollow dots up to where the session lands at the reset, red when the limit comes first) and a marker for how much of the 5-hour window has passed. Hover the bar for the details.
- **Week**: the weekly value and its bar.
- **History**: the last six hours, session as dot columns and the week as a line. Click the card for the full history.
- **Rows** to Active sessions, Statistics and All limits.

A detail screen opens in place. The header stays, and the breadcrumb (`‹ Claude / History`) leads back. Switching the provider tab or closing the popover returns to the overview.

The detail screens:

- **History**: Limits (session as dot columns, week as a red line) or Volume (tokens per day), over 1 hour to 30 days. Hover the graph for the values at that point. Below it the peak session and the weekly points added in the range.
- **Active sessions**: sessions with a transcript write in the last 5 minutes, with how long ago and their context size. Hover a row for its session ID, start time and model. Click to reveal the project in Finder, right-click to open it in Terminal or copy its path.
- **Statistics**: messages, sessions, tokens and, with **API Cost Estimate** on in Settings, the API cost for Today, 7 days, 30 days or all time, plus the top projects. Codex shows its own counts and top models.
- **All limits**: the plan, every limit with its bar and time marker, extra usage and Codex credits. Hover a limit for its reset time.

Without a Claude sign-in the Claude tab shows how to connect: load it from the keychain, or add a long-lived token in Settings. Codex keeps working in its own tab.

## Claude and Codex

With a Codex ChatGPT sign-in present, the popover gets a **Claude | Codex** switch. The menu bar shows the provider of the tab you opened last, so switching tabs is how you choose what it reports. If Codex is selected but has no data yet, the icon shows Claude's value, dimmed.

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
