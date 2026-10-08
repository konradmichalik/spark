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
- **Rows** to Active sessions, Statistics and, when there is one, More limits.

A detail screen opens in place. The header stays, and the breadcrumb (`‹ Claude / History`) leads back. Switching the provider tab or closing the popover returns to the overview.

The detail screens:

- **History**: Limits (session as dot columns, week as a red line) or Volume (tokens per day), over 1 hour to 30 days. Hover the graph for the values at that point. Below it the peak session and the peak week of the range.
- **Active sessions**: sessions with a transcript write in the last 5 minutes, with how long ago and their context size. Hover a row for its session ID, start time and model. Click to reveal the project in Finder, right-click to open it in Terminal or copy its path.
- **Statistics**: messages, sessions, tokens and, with **API cost estimate** on under **Settings → Display**, the API cost for Today, 7 days, 30 days or all time, plus the top projects as a list like the active sessions. Hover Messages, Sessions or Tokens for the averages per session and per active day (days without token use are not counted), and Tokens for what it counts. Codex shows its own counts and top models. Its counts cover local Codex CLI sessions only, so use through the Claude Code plugin, Codex Cloud or another machine moves the limit bars but not these numbers.
- **More limits**: the limits the overview does not show, such as the Sonnet, Opus and Fable weeks you enabled, or Codex's extra windows and credits, each with its bar and time marker. Hover one for its reset time. Claude's extra usage appears under the week on the overview once something was spent.

Without a Claude sign-in the Claude tab shows how to connect: load it from the keychain, or add a long-lived token in Settings. Codex keeps working in its own tab.

## Claude and Codex

With a Codex ChatGPT sign-in present, the popover gets a **Claude | Codex** switch. The menu bar shows the provider of the tab you opened last, so switching tabs is how you choose what it reports. If Codex is selected but has no data yet, the icon shows Claude's value, dimmed.

Each tab also shows that provider's session usage, colored from the warning threshold up, so both can be read without switching. Turn it off under **Settings → Display → Session usage in the tabs**. **Provider colour in the tabs** switches off the faint tint of the selected Claude tab.

If a Codex plan lacks the window picked under **Displayed value** (Pro has no 5-hour window, Free only a 30-day one), Spark uses that plan's highest window instead of showing 0%.

## Settings

- **General**: refresh mode, launch at login and the data export.
- **Menu Bar**: the glyph style and the value next to it. With Codex off, the menu bar always shows Claude.
- **Display**: bars or ring in the popover, what the popover shows (history, forecast, active sessions, statistics, top projects, API cost estimate), the model weeks listed under More limits, and the provider tab options.
- **Connections**: one card per provider with its status, plan and sign-in path. Claude's long-lived token sits behind the disclosure on its card. Codex shows `codex login` and **Check again** when it has no valid sign-in.
- **Notifications**: thresholds, events and a test notification.
- **About**: the Spark version and update check, the installed Claude Code and Codex CLI versions, the folder each provider's data is read from, and the daily totals. Spark keeps one token total per day for Claude Code so reports reach back past the days Claude Code keeps its transcripts; **Export daily totals** and **Clear daily totals** manage them.

## Notifications

A notification's title names the provider and the window, then the value (`Claude · Session at 78%`). The body says the one thing to act on: when the limit comes at the current pace, or what is left until the reset. Usage notifications carry a twelve-dot ring with the value, ochre for warning and red for critical; a reset carries an empty ring. Each provider has its own thread in Notification Center, and a click opens the popover on that provider's tab.

## Usage report

With Codex signed in, a **Provider** filter (All, Claude, Codex) under the header scopes the whole report: All adds both providers' tokens, Codex alone hides what only Claude has (pace, API cost, top projects and sessions). The calendar button in the popover header opens the report for the current week or month. It shows the tokens, the change against the period before and the API cost estimate (hover a number for the details), the pace as each day's session peak in dot columns with the week as a red line, an activity calendar (one dot per day, weeks in rows, the dot's weight showing that day's tokens against the busiest day, a ring for today, hover a day for its tokens, with the active days, longest streak and busiest day beside it), each model's share, and the top projects and sessions. Lists show three entries and expand with **Show N more**. Right-click a project to reveal it in Finder.

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

**Settings → General → Data export → Export data for other apps** (off by default) writes the current usage state to `~/Library/Application Support/Spark/data.json` on every refresh, for external consumers such as a Stream Deck plugin. Turning it off deletes the file.
