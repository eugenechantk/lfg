# Feature: Cursor-style chrome — Live Activity + session list toolbars

**Date:** 2026-07-31
**Tier:** Product (shipping TestFlight app → full workflow)
**References:**
- `.claude/feature/live-activity-cursor-style/ref-live-activity.png`
- `.claude/feature/live-activity-cursor-style/ref-session-list.png`

## User Story

As an lfg user, I want the lock-screen Live Activity and the session-list chrome to
read like the reference designs — typographic, quiet, one clear action — so that the
fleet's state is legible at a glance instead of being a dense pile of dots, pills and
badges, and so that starting a new session is the obvious bottom-of-screen gesture.

## User Flow

**A. Live Activity**
1. Agents run on the host(s); the server pushes the fleet Live Activity.
2. All working → lock screen shows a count-led list card: **"4"** + *Active*, then one
   line per session (title left, elapsed right), then *"2 More"*.
3. Any session needs input → the card switches to the attention layout: small
   *"Needs input"* label, the blocked session's title as a large 2-line headline, a
   meta line (`host · 12m · 3 working`), and a trailing **Reply** button.
4. Tapping **Reply** opens the app directly on that session.

**B. Session list chrome**
1. User opens the app → large title *Sessions* with the connection status as subtitle.
2. Top-right holds two icon buttons: **search** and **sort**.
3. Tapping search reveals the search field inline above the list; clearing/dismissing
   hides it again.
4. Tapping sort opens a menu with two options — **Status** and **Directory** — with a
   checkmark on the active one. Picking one regroups the list (same `GroupMode` state
   the segmented picker drove).
5. A composer bar is pinned above the bottom safe area: a `+` circle and the
   placeholder *"Plan, ask, build…"*.
6. Tapping anywhere on that bar presents the existing New Session sheet.

## Success Criteria

- [x] SC1: Lock-screen Live Activity with **zero** needs-input sessions renders the
  count-led list layout — big count + "Active", plain `title … elapsed` rows, no state
  dots / host pills / dividers, `+N More` overflow line —
  **Verify by:** simulator lock-screen screenshot of a seeded all-working fleet.
- [x] SC2: Lock-screen Live Activity with ≥1 needs-input session renders the attention
  layout — "Needs input" label, 2-line headline title, meta line, trailing Reply button —
  **Verify by:** simulator lock-screen screenshot of a seeded needs-input fleet.
- [x] SC3: Neither layout is center-clipped (header/label always visible) at the system's
  fixed lock-screen height —
  **Verify by:** the SC1/SC2 screenshots show the first line of the card.
- [x] SC4: Dynamic Island expanded + compact adopt the same typography (no dots/pills in
  expanded rows; compact keeps count + amber badge when needs-input) —
  **Verify by:** Dynamic Island screenshots (compact + expanded, both states).
- [x] SC5: Tapping **Reply** opens the app on the blocked session (deep link
  `lfg://session/<sid>` → `store.requestSelection`) —
  **Verify by:** open the URL against the running sim (`flowdeck` open-url) and screenshot
  the resulting `SessionDetailView`.
- [x] SC6: Session list top bar shows exactly: settings (leading), search + sort
  (trailing); no `+` button, no principal status badge; title is a large *Sessions* with
  the status as subtitle —
  **Verify by:** simulator screenshot of the list.
- [x] SC7: Search icon toggles the inline search field; typing filters the list; clearing
  restores the full list —
  **Verify by:** UI-driven screenshots (tap search → type → filtered list → clear).
- [x] SC8: Sort menu offers exactly *Status* and *Directory*, checkmarks the active one,
  and selecting one regroups the list; the segmented picker is gone —
  **Verify by:** UI-driven screenshots of the open menu and both groupings.
- [x] SC9: Bottom composer bar is pinned above the safe area on the list screen and
  tapping it presents the New Session sheet —
  **Verify by:** UI-driven screenshot of the bar + screenshot after the tap.
- [x] SC10: `swift test` in `ios/LFGCore` stays green (no model/regressions) —
  **Verify by:** recorded `swift test` output.

## Platform & Stack

- **Platform:** iOS 18+/26 (SwiftUI), WidgetKit + ActivityKit
- **Language:** Swift 6, strict concurrency
- **Key files:** `ios/LFGWidgets/LFGSessionActivityWidget.swift`,
  `ios/LFG/SessionListView.swift`, `ios/LFG/RootView.swift`, `ios/project.yml`

---

## Design spec — Live Activity

The reference stacks two cards. We ship **one** fleet activity, so the two card
*styles* become two **states** of the same card.

Shared: near-black translucent background (keep `.activityBackgroundTint(.black.opacity(0.84))`),
horizontal padding 18, vertical padding 14, no dividers anywhere, no glyph/app mark,
no state dots, no host pills.

### State B — all working ("Active" list card; reference card 2)

```
5  Active                     ← count .title2.bold white + "Active" .body secondary,
                                 firstTextBaseline-aligned, spacing 6
Enable dark mode        1m    ← .subheadline primary / .subheadline secondary monospacedDigit
Address CI failures     2m
Scaffold Kotlin scheme  4m
2 More                        ← .footnote tertiary
```
- Row list spacing 7; each row is `title (lineLimit 1, truncate tail, layoutPriority 1)`
  + `Spacer` + `elapsed`.
- Elapsed = compact relative from `row.since` ("now", "3m", "1h 4m") — the existing
  timer treatment stays but drops to secondary weight; no colored accent.
- Try **3** rows on the lock screen. The prior 2-row cap came from a taller header
  (26pt mark) + dividers + pills; this layout is materially shorter. If SC3's screenshot
  shows clipping, fall back to 2 and record it in the Decision Log.

### State A — any needs input ("attention" card; reference card 1)

```
Needs input                            ← .footnote secondary (amber when count > 1:
                                          "2 need you")
Redesign live activity widget          ← .title3.weight(.semibold) white, lineLimit 2
pro · 12m · 3 working        [ Reply ] ← meta .footnote secondary   button:
                                          .subheadline.weight(.medium) white on
                                          .white.opacity(0.14), radius 14, h14/v7
```
- Hero row = the first `blocked` row (rows already arrive needs-input-first).
- Meta = `host` · elapsed · `N working` (omit the working clause when 0). When more than
  one session needs input, append `· +N more need you`.
- Button is `Link(destination: URL(string: "lfg://session/\(sid)"))`.
- Amber (`.orange`) is the ONLY accent, and only on the label — everything else is
  white/secondary. No orange pills.

### Dynamic Island

- **compactLeading / minimal:** unchanged (dot; amber when needs-input else blue).
- **compactTrailing:** unchanged (count, amber badge when needs-input).
- **expanded leading:** the state-B header (`N` + "Active") or state-A label + title,
  one line, `.minimumScaleFactor(0.6)`.
- **expanded bottom:** 2 rows in the state-B row style (no dividers, no dots, no pills).

### Deep link

- Register `CFBundleURLTypes` with scheme `lfg` in the LFG target's `info.properties`
  in `ios/project.yml` (then `xcodegen generate`).
- `RootView` gains `.onOpenURL { }`: for `lfg://session/<sid>`, call
  `store.openFromNotification(sid)` — reuses the existing deferred-selection path that
  already avoids the mutate-during-view-update crash. Ignore anything else.

---

## Design spec — session list chrome

### Top bar

| Placement | Now | After |
| --- | --- | --- |
| leading | gear (settings) | gear (settings) — unchanged |
| principal | `StatusBadge` (iPhone) | *(removed)* |
| trailing | `+` new session | `magnifyingglass` toggle, then `line.3.horizontal.decrease` sort menu |

- Title: `.navigationTitle("Sessions")` with `.large` display mode on **both** idioms
  (iPhone previously had an empty inline title), and `sidebarStatusSubtitle(statusSubtitle)`
  on both — the subtitle already carries the multi-host online/offline story that the
  removed `StatusBadge` was showing. Keep `StatusBadge`/`HostStatusChip` types (still used
  nowhere else? — if unused after this, leave them in place; removal is out of scope).
- **Search:** `@State private var showSearch`. Toggling shows the existing `searchField`
  above the list with `@FocusState` focus; hiding clears `searchText`. Animate with
  `.easeInOut(0.2)`. Keep the existing filtering logic untouched.
- **Sort:** replace the segmented `Picker` with a toolbar `Menu` bound to
  `settings.groupMode`:
  ```
  Menu { Picker("Sort", selection: $settings.groupMode) {
            Text("Status").tag(GroupMode.status)
            Text("Directory").tag(GroupMode.directory) } }
       label: { Image(systemName: "line.3.horizontal.decrease") }
  ```
  (A `Picker` inside a `Menu` gives the checkmark for free.) `GroupMode` already has
  exactly these two cases — do not add cases.

### Bottom composer bar

- New view `NewSessionBar` in `SessionListView.swift`, pinned via `.safeAreaInset(edge: .bottom)`
  on the `List`.
- Anatomy: `+` in a 30pt circle (`.white.opacity(0.10)` fill, `.secondary` glyph), then
  `Text("Plan, ask, build…")` `.subheadline` `.secondary`, `Spacer`.
- Container: capsule, `.regularMaterial` background, `.horizontal 16 / .vertical 10`
  inner padding, outer `.horizontal 16 / .bottom 10`, subtle `.white.opacity(0.08)` stroke.
- Whole bar is one `Button` → `showNewSession = true`; `.buttonStyle(.plain)` +
  `.contentShape(Capsule())`. `accessibilityIdentifier("newSessionBar")`.
- Only on the list screen (it lives inside `SessionListView`, so the detail column and
  iPad detail pane are unaffected).

## Steps to Verify

1. `cd ios/LFGCore && swift test` — green.
2. Build + install to a booted simulator via FlowDeck; the widget extension ships with it.
3. Live Activity: seed the fleet activity locally (see `FleetActivityController` /
   `.claude/feature/evidence-live-activity/` for how the prior evidence was produced) in
   both states; lock the sim; screenshot lock screen + Dynamic Island.
4. Deep link: open `lfg://session/<sid>` against the sim; screenshot the opened session.
5. List chrome: screenshot the list; tap search → type → screenshot; open the sort menu →
   screenshot → switch to Directory → screenshot; tap the bottom bar → screenshot the sheet.
6. Store artifacts in `.claude/feature/evidence-cursor-style-chrome/`.

## Implementation Phases

### Phase 1: Live Activity restyle + deep link
- Scope: `ios/LFGWidgets/LFGSessionActivityWidget.swift` (rewrite views),
  `ios/project.yml` (URL scheme), `ios/LFG/RootView.swift` (`onOpenURL`).
- Criteria: SC1–SC5, SC10.
- Gate: `swift test` green + lock-screen/DI screenshots for both states + deep-link screenshot.

### Phase 2: Session list chrome
- Scope: `ios/LFG/SessionListView.swift` (toolbar, search toggle, sort menu, bottom bar),
  large title on iPhone.
- Criteria: SC6–SC9, SC10.
- Gate: `swift test` green + UI-driven screenshots of search, sort menu, both groupings,
  bottom bar, and the presented sheet.

## Decision Log

- **2026-07-31 — One card, two states (not two cards).** The reference stacks a "Finished"
  hero card and an "Active" list card because it runs one activity per task. We ship a
  single fleet activity by design (see `.claude/brainstorm/live-activity-redesign.md`), so
  the two card styles map onto our two fleet states: attention layout when any session
  needs input, list layout otherwise. *Alternative:* always use the list layout — rejected,
  it loses the reference's best idea (the actionable item gets the headline + one button).
- **2026-07-31 — Host names drop out of the list rows.** Reference rows are `title … time`
  only. Host survives in the attention layout's meta line, and the offline-host warning
  survives via the existing `hosts` status array only where it matters (a blocked session's
  meta). *Alternative:* keep the host pill — rejected, it's the single densest element and
  the reason the current card reads as cluttered.
- **2026-07-31 — Bottom bar omits the reference's mic glyph.** There is no
  dictation-to-session path in the app; keyboard dictation already covers it once the sheet
  is open. A mic button that only opens a sheet would be a lie. *Alternative:* include it as
  a second sheet trigger — rejected.
- **2026-07-31 — iPhone gains the large "Sessions" title + status subtitle.** The reference's
  chrome is large-title-led, and dropping the principal `StatusBadge` (to make room for
  search + sort) needs the status to land somewhere; `statusSubtitle` already exists and
  already handles multi-host. *Alternative:* keep the badge and drop the settings gear —
  rejected, settings must stay reachable.
- **2026-07-31 — Lock screen ships 3 rows, not 2.** The prior redesign capped the card at
  header + 2 rows because header + 3 clipped. Verified empirically that the stripped-down
  layout (no 26pt mark, no dividers, no pills) fits 3 rows with the header intact.
- **2026-07-31 — `+` toolbar button removed.** The bottom bar is now the new-session
  affordance; two entry points in one screen is noise.

## Verification Evidence

Device: iPhone 17 Pro simulator `E0DC8228-3248-4630-8929-FBC5DFC6AE6D` (iOS 26.3),
dedicated DerivedData (two other agents were building this repo concurrently).
Live Activity states seeded through the app's existing `LFG_LA_MOCK` debug hook
(`working` = all-working fleet, `1` = needs-input fleet). Artifacts in
`.claude/feature/evidence-cursor-style-chrome/`.

| SC | Method run | Result | Artifact |
| --- | --- | --- | --- |
| SC1 | Launch with `LFG_LA_MOCK=working`, lock screen | PASS — "**3** Active" + 3 plain `title … elapsed` rows, no dots/pills/dividers/glyph | `06-la-working.png` |
| SC2 | Launch with `LFG_LA_MOCK=1`, lock screen | PASS — amber "2 need you", 1-line headline, `pro · 3m · 2 working · +1 more need you`, Reply button | `07-la-needsinput.png` |
| SC3 | Inspect SC1/SC2 captures for center-clipping | PASS — first line visible in both; **3 rows fit**, the old 2-row cap was an artifact of the heavier header | `06`, `07` |
| SC4 | Home screen compact + long-press expanded, both states | PASS — compact keeps dot + amber `2 ▲`; expanded shows summary + 2 plain rows | `10`–`13` |
| SC5 | Tap Reply on lock screen; then `open-url lfg://session/<real sid>` | PASS — Reply launches the app into the session route; real sid opens that session's transcript | `08-reply-tap.png`, `09-deeplink-real-session.png` |
| SC6 | Screenshot list | PASS — gear leading, search + sort trailing, no `+`, no principal badge, large "Sessions" + "Connected · 3 running" subtitle | `01-list-chrome.png` |
| SC7 | Raw-HID tap search toggle → type "codex" → toggle off | PASS — field reveals focused, list filters to 4 matches, toggling off clears the query and restores the full list | `02-search-active.png` |
| SC8 | Raw-HID tap sort → screenshot menu → select Directory | PASS — menu shows exactly Status (✓) / Directory; selecting Directory regroups; segmented picker gone | `03-sort-menu.png`, `04-sort-directory.png` |
| SC9 | Tap `newSessionBar` | PASS — New Session sheet presents | `05-newsession-sheet.png` |
| SC10 | `cd ios/LFGCore && swift test` | PASS — 145 tests, 0 failures (count rose from 141 mid-session; a concurrent agent added 4) | — |

Build: `flowdeck run -s LFG` clean for both the `LFG` app target and the embedded
`LFGWidgets` extension. `xcodegen generate` clean. The SourceKit diagnostics that
appear when the widget file is opened standalone (`Cannot find 'LFGFleetAttributes'`)
are an editor artifact of the shared-file target membership, not build errors.

## Bugs

All three were found in the verification pass and fixed inline (review-pass exception),
then re-verified.

1. **Large title rendered blank while searching, leaving ~90pt of dead space.** The
   large title lays out against the first scrollable descendant; revealing the search
   field above the `List` broke that association. Fixed by collapsing to
   `.inline` while `showSearch` is true. Re-verified in `02-search-active.png`.
2. **Expanded Dynamic Island leading region was unreadable.** The spec asked for label
   + hero title in that narrow region; both scaled to 0.6 and clipped on each side.
   Fixed by showing the summary label only — the titles are already the rows below.
   Re-verified in `11-di-expanded.png`.
3. **Expanded island rows clipped at both edges** (first glyph of each title, trailing
   elapsed) against the island's rounded corners. Fixed with 6pt horizontal padding on
   the bottom region and 6pt leading padding on the header. Re-verified in `11`, `13`.
