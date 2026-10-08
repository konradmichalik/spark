# Design rules

These rules are binding for every change to Spark's UI, the app icon, notifications and the website. When a change needs to break one, change the rule here first, in the same pull request, and say why.

The screens these rules produce are listed in [screens.md](screens.md).

## Principles

1. **Neutral, not branded by a provider.** Spark tracks several providers. No provider's colour, mark or naming carries the brand.
2. **The important part first.** Level 1 answers "how much is left and will it last". Everything else is one click away.
3. **Ink for data, colour for meaning.** Colour appears only where it tells the user something: the brand dot, the weekly line, warning, critical.
4. **Dots, sparingly.** The dot language is the identity. Use it for marks and big numbers, never as decoration.
5. **Calm by default.** Nothing moves unless it reports a change.

## Colour

All colours come from `Theme` tokens with a light and a dark value. No literal colours in views.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `paper` | `#F2F2EF` | `#1C1C1B` | Popover and window background |
| `card` | `#FAFAF8` | `#262625` | Cards and row groups |
| `ink` | `#111111` | `#EDEDE8` | Text, filled dots, primary marks |
| `inkSecondary` | `#5C5C58` | `#A3A39D` | Secondary text, labels |
| `inkTertiary` | `#6E6E69` | `#8F8F8A` | Axis labels, chevrons |
| `hairline` | `#E4E4DF` | `#333331` | Card outlines, separators |
| `dotTrack` | ink at 15 % | ink at 16 % | Unfilled dots |
| `accent` | `#D71921` | `#FF5A5F` | Brand red |
| `warning` | `#B07800` | `#F0B429` | Warning ochre |
| `claudeLogo` | `#C96442` | `#C96442` | Claude's logo and the faint tint of its selected tab, nothing else |

- **Red is the brand colour and is not configurable.** It marks the logo's centre dot, the weekly line in graphs, and any value at or above the critical threshold.
- **Ochre marks values between the warning and the critical threshold.** Nothing else is ochre.
- **No provider colour in data.** Bars, rings, graphs and numbers are ink, ochre or red, whichever provider they belong to. A provider's colour appears only in its logo in the tab and as a faint tint of the selected tab, and the user can switch it off.
- Status colours must differ from ink in lightness, not only in hue.
- `warning` reaches 3:1 on `card`, so it colours large numbers and graphics only; small warning text also needs an icon or the word.

```swift
// Colour state is derived in one place, never per view.
let tone = UsageTone(value: 78, warning: state.warningThreshold, critical: state.criticalThreshold)
tone.color // Theme.warning
```

`UsageTone` and the tokens live in `Spark/Sources/Models/DesignTokens.swift`. The old orange values in `Theme` are removed as the screens move over.

## Typography

| Role | Font | Size and weight |
| --- | --- | --- |
| Hero value (session) | Doto | 60pt, weight 900 |
| Stat tiles, report totals | Doto | 24 to 48pt, weight 900 |
| Wordmark `spark` | Doto | weight 800 |
| Body and labels | SF Pro | 11 to 13pt |
| Micro labels (`SESSION`, `WEEK`) | SF Mono, uppercase, tracking 1.5 | 10pt |
| Axis labels | SF Mono | 10pt |

- **Doto only for large numbers and the wordmark.** If a number is smaller than about 20pt, it is SF Pro with tabular digits.
- **Units are never set in Doto.** `%`, `K`, `M`, `B` and `$` follow the number in SF Pro, smaller and semibold. Prefixes such as `~` and `≈` are treated the same way.
- **10pt is the minimum** for text. The one exception is the 9pt micro label over the forecast and burn rate facts in the session block; the 8pt `%` inside the Settings style thumbnail is part of an illustration, not text.
- Doto is bundled with its OFL licence. Do not use `xeji01/nothingfont`: it redistributes Nothing's proprietary NDot files under a licence restricted to Nothing brand material.

```swift
HStack(alignment: .firstTextBaseline, spacing: 3) {
    Text(value).font(.doto(size: 60))
    Text("%").font(.system(size: 20, weight: .semibold))
}
.lineLimit(1)
.minimumScaleFactor(0.6)
```

`Font.doto(size:weight:)` lives in `Spark/Sources/Views/Components/DotoFont.swift`.
- Micro labels are one line. They truncate instead of wrapping, so the value under them never moves; keep them short ("VS LAST WEEK", not "VS PREVIOUS WEEK").

## Numbers and units

- Percent goes through the locale formatter. Never build `"\(value)%"` by hand.
- Tokens are compact: `536.9K`, `6.8M`, `2.7B`.
- API cost depends on its size, so a tile never holds more than five characters:

| Value | Shown as |
| --- | --- |
| below 100 | `84.20` |
| 100 to 9,999 | `117`, `7,015` |
| 10,000 and above | `48.2K` |

- Durations are short: `1h 49m`, `3d 18h`. An absolute time goes in a tooltip.
- API cost is always marked as an estimate (`≈`) and its tooltip says it is priced at API list prices, not the subscription.
- "Tokens" always means fresh tokens: input, output and cache writes for Claude, input and output for Codex. Cache reads and cached input are never part of a headline figure, a graph or a tile, and the tooltip says so (`TokenWording`).

## Dot language

| Element | Shape | Used for |
| --- | --- | --- |
| Dot bar | One row of dots, 6pt pitch (session) or 4pt (week and limits) | Usage on level 1 and in More Limits |
| Dot ring | 40 dots for the session with a two-dot gap at twelve o'clock, so start and end stay visible | Display style "Ring". The week stays a dot bar beside it |
| Menu bar ring | 12 dots, the last partial dot at proportional opacity | Menu bar glyph |
| Hollow dots | Outline only, from current value to projected value | Session projection |
| Time marker | 2pt vertical stroke, or a short radial tick outside a ring | Share of the window already elapsed, on the session and the week |
| Activity calendar | One dot per day, weeks in rows and weekdays in columns (first weekday of the system calendar). Levels by fresh tokens against the provider's busiest day of the period: no use is a 4pt `dotTrack` dot, then 8pt ink at 35 %, 60 % and 100 %. Today gets a 1pt ink ring, days after today are not drawn | Usage report, one calendar per provider |
| Dot columns | Vertical stacks of dots | Session history in graphs. Three or more empty columns in a row collapse into one `dotTrack` band at most 6pt wide, and the week line breaks there. A week point alone between two gaps is drawn as a dot |

- Filled dots are `ink`, or `warning` or `accent` by threshold. Unfilled dots are `dotTrack`.
- The fill takes its colour from the user's thresholds. Projection dots, the time marker and the forecast line take theirs from the forecast: ink while the session lands below 90 %, `warning` from 90 %, `accent` when it reaches the limit before the reset. Hollow dots always draw at 55 % of that colour, the marker and the line at full strength, the line in regular weight. Beside the session number, two short facts (9pt micro label, 11pt value) say where the session lands ("FORECAST": "~79% at reset" or "Limit 1h 4m early", in the forecast's tone) and how fast it goes ("BURN RATE": "25.5K/min"). Each explains itself in its own tooltip, so the bar tooltip only explains the marks. The ring style shows only the forecast and puts the burn rate in the ring tooltip. The forecast uses only the current session and waits for 15 minutes of data ("Forecast after 15 min").
- The weekly series in graphs is always a solid `accent` line over grey dot columns. The two series are told apart by shape, not by a second colour.

## Layout

| Element | Value |
| --- | --- |
| Popover width | 320pt, content 292pt |
| Popover padding | 14pt |
| Gap between blocks | 16pt |
| Card radius and padding | 10pt, 10 to 12pt |
| List row height | at least 34pt |
| Tab height | 30pt |
| Icon button | 26pt square |

- Group with cards and whitespace, not with dividers. A hairline only inside a card, between rows.
- One header for every popover screen (`PopoverHeader`). Row 1 never changes: mark, wordmark, report, settings.

## Navigation

- **Two levels, never three.** Level 1 is the overview of the selected provider. Level 2 screens are pushed inside the popover: History, Active Sessions, Statistics, More Limits.
- On level 2 the tab row becomes a breadcrumb at the same height: `‹ [logo] Claude / History`. Plain text, hairline below, no pill.
- Anything clickable on level 1 that leads deeper is a card or a row with a chevron. The whole card is the hit target.
- Each row leads with a 13pt icon in the dot language: a pulsing `accent` dot for active sessions (still when none is active or under Reduce Motion), three dot bars for statistics, a partly filled dot octagon for more limits. The statistics row shows the token count, never the API cost; the cost lives on the statistics screen.
- Settings tabs keep the system symbols; dot icons at tab size read poorly.
- The service status (overview status row, Settings > Status) is one status dot: a plain dot while operational, a dot with the live halo in `warning` for a degraded service or partial outage and in `accent` for a major outage, and a hollow ring while the status cannot be read.
- Long lists show the first entries and a "Show N more" row that expands in place.
- Provider tabs show logo, name and session value and are never truncated. A fifth provider goes into a "More" tab.
- The selected tab is persisted and is the provider the menu bar shows.

## Detail screens

- Switches use `PaperSegments`: a trough with the selected segment raised as a card for modes and periods, small mono chips with the selected one in ink for graph ranges.
- History shows the peak session and the peak week of the range under the graph, both in percent. A weekly reset does not lower the peak.
- Stat tiles go two to a row. With the API cost estimate switched off in Settings, Tokens takes the whole second row.
- "Show N more" appears only when at least two entries are hidden; a single extra entry is shown right away. An expanded list of more than ten entries scrolls.
- More Limits lists only what the overview does not show: the model weeks the user enabled (Claude) and extra windows (Codex). Session and week are never repeated, Claude's extra usage sits under the week on the overview once something was spent, and the plan is in the tab tooltip. The row only exists when there is at least one such limit. Codex credits are set apart with a hairline outside a card, the one exception to "hairlines only inside a card". A warning or critical percentage there carries an alert icon, because 13pt ochre text alone does not reach 4.5:1.
- Without a Claude sign-in the popover still opens. The Claude tab shows the not-connected state and other providers stay usable in their tabs.

## Tooltips

- One component, one style: ink background, paper text, uppercase SF Mono title, one to three lines.
- No actions inside a tooltip.
- At most one tooltip visible.
- The Statistics tiles carry their averages in tooltips (per session, and per active day once more than one day had tokens; idle days never count), and the Tokens tooltip explains fresh tokens against cache reads. Top projects and top models are a card of rows like the active sessions, without bars.
- Tooltips carry the secondary facts so the screen does not have to: plan and sign-in path on a tab, projection and burn rate on the session bar, reset times on limits, session ID and model on a session row, the meaning of API cost.

## States

| State | Treatment |
| --- | --- |
| Normal | Ink |
| Warning (≥ warning threshold) | Value, bar and menu bar glyph in `warning` |
| Critical (≥ critical threshold) | Value, bar and menu bar glyph in `accent` |
| Stale or error | Menu bar label at 35 % opacity when the connection is lost, Codex needs a new sign-in, the shown provider reports an error, or the last update is older than an hour; existing status row in the popover |
| Not connected | Empty dot ring with a link icon, one sentence, one primary action, one secondary link |

Other providers stay usable when one is disconnected.

## Menu bar

- Template image, 16pt, so the system can tint it on the transparent macOS 26 menu bar.
- Shows the value of the selected popover tab.
- Styles (Settings > Menu Bar): ring, or ring with the provider logo in front. "Displayed Value: None" hides the number and leaves the ring alone.
- Only warning and critical break out of the template colour.

## Notifications

- Title: provider and window, then the value: `Claude · Session at 78%`.
- Body: the one thing to act on, usually the projection or the time to reset.
- Usage notifications attach a generated twelve-dot ring with the value, coloured by state. Resets attach an empty ink ring. System messages have no attachment.
- One `threadIdentifier` per provider (`claude`, `codex`), and `spark` for messages about Spark itself. A click opens the popover on that provider's tab.
- The ring attachment is a 64pt tile on `card`, rendered in the app's current appearance. The value in its centre is SF Pro bold, not Doto: at that size Doto stops reading.
- Wording lives in `NoticeWording` (`Spark/Sources/Models/SparkNotice.swift`), never inline at the trigger.

## Windows

- Settings and the usage report use the popover's tokens: `paper` background, `card` with a hairline outline, sentence-case section titles in `inkSecondary`. Rows inside a settings card are separated by hairlines.
- Switches are ink. Segmented choices use `PaperSegments`, buttons `PaperButtonStyle`: a hairline fill, or ink for the one main action.
- A choice between looks (bars or ring, menu bar style) is a pair of preview cards; the selected one is outlined in ink.
- A connection card leads with the provider's logo, its name and a status line (state, plan, sign-in path). The status dot is ink when connected, `accent` when the sign-in expired, `warning` when none was found and `dotTrack` when switched off; the words always say the same, so the dot is never the only signal. There is no green.
- Claude has no show switch on its card: Claude cannot be hidden.
- The report window takes the height of its content, so the whole report shows without scrolling, keeping its top edge and never growing past the visible screen; only then does it scroll. It refits when the period or provider changes. The three totals share one Doto size, set by the longest value (40, 36, 32 or 28 pt), so they read as one line.
- Every report section sits on its own card (`ReportCard`: `card` with a hairline outline, 14 pt inside, 12 pt between cards): the totals, the pace graph, the activity calendar with its figures, By model, Top projects and Top sessions. By model and Top projects share a row and are as tall as the taller one. The lists inside a card still space their rows instead of ruling them, and show three entries and "Show N more".
- A provider filter (`PaperSegments`, "Provider": All, Claude, Codex, full width) sits directly under the report header, only while both providers count: Codex is active, or signed out with local data in the period. With one provider there is no filter and the report is Claude's. It defaults to All and is not remembered.
- The filter scopes the whole report. All adds Claude and Codex fresh tokens, for the total, the change against the previous period and the activity calendar. Claude shows Claude only. Codex shows its tokens, change, activity calendar and models, and hides the pace graph, API cost, top projects, top sessions and the cache and price notes, which only exist for Claude. In All, those Claude-only sections keep their place and carry "CLAUDE" in their title, and the API cost tooltip says it covers Claude only. By model lists both providers' models, largest first.
- The activity calendar sits after the pace graph: one calendar for the selected scope, no provider logos and no provider colour. A day's tooltip (150 ms) gives the date and its fresh tokens, or "No use". A legend line ("Less" to "More") sits under it. Beside it, in a second column like By model and Top projects (under it when the window is too narrow), three figures for the scope: active days ("3 of 9 days", days up to today), the longest streak of days in a row, and the busiest day with its tokens (the latest on a tie), each a micro label over a Doto number with its words in SF Pro, each with a tooltip and one VoiceOver element. The calendar is one VoiceOver element that names the active days and the busiest day, and nothing in it moves.

## Motion

Motion is added only when `accessibilityReduceMotion` is off. Start from no motion and opt in.

| Where | What | Duration |
| --- | --- | --- |
| Dot bar and ring | Filled dots appear in sequence, 25 ms apart and closer when more must fit, on appear and when the value rises; a falling value shows at once. Session bar, ring, week bar, More Limits bars | 300 ms total |
| Hero value | `.contentTransition(.numericText())` on the session number (bars and ring) and the week value, when the whole percent changes | 250 ms |
| Projection | Hollow dots breathe between full and 35 % opacity, only when the forecast reaches the limit before the reset, bar and ring. The hollow dots sit on their own layer, so only that layer's opacity changes and the filled dots are not redrawn | 2 s loop |
| Level 2 | Push from the right, header fixed | 220 ms |
| Live dot | Soft halo grows from 40 % to 95 % of the icon and fades, then restarts, only while the session is active. Overview row and Active Sessions rows alike, never in the menu bar | 2.4 s loop |
| Tooltip | Fades in with a 4 pt rise after the 400 ms delay, 150 ms on usage blocks (the whole block is the hover target); hides at once | 120 ms |
| Tabs | Selected background slides | 200 ms |
| Spark mark | While the app loads, the ring dots light up in turn, one step every 110 ms; it stands still when loading ends and under Reduce Motion | 110 ms per step, loop |
| Menu bar | When the value rises, the new dots fade in over two in-between images and the final one, started by the value change only. No loop, no `TimelineView` in the label | 3 × 84 ms |

Loops (live dot, projection) run as their own phase loops on layers that only scale or fade, so re-renders and animations around them cannot re-target them, and each starts from the same state. A loop starts 300 ms after its view appears, and no transaction from the popover (screen change, window resize) reaches the live dot, so a halo can only scale and fade in place. Under Reduce Motion everything shows its end state at once.

Nothing else moves. No looping animation without a reason the user cares about.

## Accessibility

- Text contrast at least 4.5:1, large numbers and graphics at least 3:1, in light and dark.
- Every icon-only button has an accessibility label. Decorative marks are hidden from VoiceOver.
- Graphs and rings have an accessibility value that states the numbers in words.
- Check every screen with Increase Contrast and Reduce Transparency on.

## Copy

- The app is English. Sentence case for labels and buttons.
- Name things the same way everywhere: Session, Week, History, Active Sessions, Statistics, More Limits, API cost.
- Provider and window in that order, separated by ` · `.

## Brand

- Mark: twelve dots on a circle, nine filled, three at low opacity, one red dot in the centre.
- Wordmark: `spark` in lowercase Doto, weight 800.
- The centre dot is always red. The mark itself is ink on paper, or paper on ink.
- The Claude asterisk and Claude orange are not part of Spark's brand. Provider logos appear only to identify a provider.

## Landing page

- `site/` is plain HTML, CSS and one small script, no build step, no framework. Tokens are the colour table above as CSS custom properties, light and dark through `prefers-color-scheme`.
- Doto is self-hosted from `site/` (`Doto-Variable.ttf` with `Doto-OFL.txt`, linked in the footer). No Google Fonts, CDN, analytics or other third-party request: the only outbound links are the ones a visitor clicks. Body text uses the system stack.
- The product shots are inline SVG and CSS built from the same tokens and dots as the app (popover, menu bar ring, activity calendar), never screenshots. They use example values and stay marked as an image for assistive technology.
- Numbers on the page are facts a reader can check in the repository (providers, minimum macOS, poll interval, dependencies), not usage figures. The install band stays dark in both schemes.
- Layout is fluid down to 320 px with a 16 px gutter and no horizontal scroll. Motion only inside `prefers-reduced-motion: no-preference`.

## Pull request checklist

- [ ] Colours come from `Theme` tokens, no literals
- [ ] Doto only for large numbers and the wordmark, units in SF Pro
- [ ] Numbers go through the shared formatters
- [ ] No new third navigation level, no new dividers between cards
- [ ] Secondary facts in a tooltip, not on the screen
- [ ] Light, dark, Increase Contrast and Reduce Motion checked, screenshot in the PR
- [ ] A rule that changed is updated in this file
