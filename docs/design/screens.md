# Screen designs

The reference designs for every Spark screen. They live on a design canvas: https://claude.ai/artifact/8MahAu9PcXKj4cbymZ6YZh. The canvas is private to its owner until it is shared from its Share menu.

Use the rows labelled **A3**. The rows A, B, C and A2 above them are earlier explorations and are not the target.

The mockups use German copy. The app is English, so translate labels instead of copying them. Values in the mockups are examples.

The rules behind these screens are in [rules.md](rules.md). The previews are exports of the canvas; click one for the full size. When a board changes on the canvas, export it again and replace its file in `screens/`.

## Popover

| Board | Screen | What it settles | Preview |
| --- | --- | --- | --- |
| 1 | Overview, bars | Level 1 layout: header, provider tabs, session with projection and time marker, week, history card, row group, footer with refresh | <a href="screens/01-overview-bars.png"><img src="screens/01-overview-bars.png" width="140" alt="Board 1"></a> |
| 1d | Overview, dark mode | Dark token values and the brighter red | <a href="screens/01d-overview-dark.png"><img src="screens/01d-overview-dark.png" width="140" alt="Board 1d"></a> |
| 2 | Overview, rings | Display style "Rings": session and week as dot rings, the plan tooltip on a tab | <a href="screens/02-overview-rings.png"><img src="screens/02-overview-rings.png" width="140" alt="Board 2"></a> |
| 3 | Codex | Same structure for a provider with two windows, tab tooltip with plan and sign-in path | <a href="screens/03-codex.png"><img src="screens/03-codex.png" width="140" alt="Board 3"></a> |
| 4 | History | Limits and Volume switch, range, crosshair tooltip that reads both series | <a href="screens/04-history.png"><img src="screens/04-history.png" width="140" alt="Board 4"></a> |
| 5 | Active Sessions | Session rows, row tooltip with ID and model, "Show N more" in place | <a href="screens/05-active-sessions.png"><img src="screens/05-active-sessions.png" width="140" alt="Board 5"></a> |
| 6 | Statistics | Period switch, four Doto tiles including API cost, top projects | <a href="screens/06-statistics.png"><img src="screens/06-statistics.png" width="140" alt="Board 6"></a> |
| 7 | All Limits, Claude (now "More limits": model weeks only, see rules.md) | Plan line, every limit as a dot bar, warning and critical examples | <a href="screens/07-all-limits-claude.png"><img src="screens/07-all-limits-claude.png" width="140" alt="Board 7"></a> |
| 8 | All Limits, Codex (now "More limits": extra windows and credits only) | The same screen with Codex's two windows | <a href="screens/08-all-limits-codex.png"><img src="screens/08-all-limits-codex.png" width="140" alt="Board 8"></a> |
| 9 | Not connected | Empty state with one primary and one secondary action | <a href="screens/09-not-connected.png"><img src="screens/09-not-connected.png" width="140" alt="Board 9"></a> |

## Windows and system surfaces

| Board | Screen | What it settles | Preview |
| --- | --- | --- | --- |
| 10 | Settings, Display | Bars or rings as preview cards, popover content toggles | <a href="screens/10-settings-display.png"><img src="screens/10-settings-display.png" width="200" alt="Board 10"></a> |
| 10b | Settings, Connections | One card per provider, long-lived token disclosure, signed-out Codex | <a href="screens/10b-settings-connections.png"><img src="screens/10b-settings-connections.png" width="200" alt="Board 10b"></a> |
| 11 | Usage report | Doto totals, pace graph, by model, top projects | <a href="screens/11-usage-report.png"><img src="screens/11-usage-report.png" width="200" alt="Board 11"></a> |
| 12 | Menu bar and tooltip | Glyph in a light and a dark menu bar, all glyph variants and states, tooltip style | <a href="screens/12-menu-bar.png"><img src="screens/12-menu-bar.png" width="200" alt="Board 12"></a> |
| 13 | Motion | Every animation with its real duration. The preview is a still, the canvas plays them | <a href="screens/13-motion.png"><img src="screens/13-motion.png" width="200" alt="Board 13"></a> |
| 14 | Notifications | Title and body wording, ring attachment per state, threads | <a href="screens/14-notifications.png"><img src="screens/14-notifications.png" width="200" alt="Board 14"></a> |
| 15 | Landing page | `site/` layout, fluid down to phone width | <a href="screens/15-landing-page.png"><img src="screens/15-landing-page.png" width="200" alt="Board 15"></a> |

## Building blocks

| Board | Component |
| --- | --- |
| Popover header | `PopoverHeader`: mark, wordmark, report and settings buttons, provider tabs or breadcrumb |
| Tooltip | The single tooltip style |
