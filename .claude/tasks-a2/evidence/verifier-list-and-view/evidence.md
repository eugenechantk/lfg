# Verifier evidence: Tasks list + task view vs A2 dark boards

Date: 2026-10-15 · Verifier: claude-design-verifier (independent) · Verdict: **FAIL**

## Scope

- Design ground truth: boards served at `http://127.0.0.1:8931/` and rendered in Chrome (390×844, DPR 1): `tA2d-list`, `tA2d-detail` (+ Pause → paused), `tA2d-detail-failed` (+ Retry now → retrying), `tA2d-detail-input` (+ option 1 → answered). Expected values come from the rendered DOM (inline styles / computed styles) and the rendered pixels, not from the feature doc.
- App: simulator `1D902A87-40EB-40AF-87A6-BBC19508900B` (iPhone 17 Pro, dark), FlowDeck screenshots at 1x (402×874 pt = px). Stand-in host on 127.0.0.1:8932 plus two real hosts.
- States exercised in the app: list (All hosts and Pro filter, Closed expanded, scrolled), task view next run, paused (Pause → Resume), failed, retrying (Retry now), waiting, answered (option 1), ••• menu. Fixture reset afterwards (new fixture PID 85111; log in the session scratchpad `fixture-verifier.log`).

Measurement notes: app screenshots are 1x, so 0.5 pt hairlines cannot be colour-matched exactly. The Chrome JPEG shifts colours slightly (`#1C1C1E` renders as 26,26,28), so design colours are quoted from the board's DOM tokens. Large text and fills are measured on both sides with `meas.py` (ink bounding boxes and dominant colours).

## Per-component table

### List (`tA2d-list`)

| Component | Internal consistency | Structure | Copy | Typography | Colour | Glyphs | Spacing | States |
|---|---|---|---|---|---|---|---|---|
| Top bar (status + search/••• pill) | PASS | PARTIAL: no running count in the multi-host form | data ("3 hosts online") | FAIL (minor): 14 pt vs 16 pt | PASS | native SF symbols, about 25% larger | native: 44 pt pill vs 48 | PASS: pinned while the list scrolls, with a soft edge |
| Section headers | PASS | PASS: 4 sections in order, Closed collapsed, "by next run" hint | PASS | PASS (15 semibold) | **FAIL**: count colour | PASS (chevron 11×7 vs 8×5) | **FAIL**: 52 pt vs 38 pt | PASS: collapse and expand work |
| Rows (time, title, schedule, result, chevron) | PASS: uniform black, no seams | PASS | PARTIAL: schedule wording, failure reason | PASS: 17/15/13, row 87 pt vs 87.5 | PASS: amber, red, green, white, grey time tones | PARTIAL: chevron 7×12 vs 5×8, ask glyph 14×13 vs 10×10 | PARTIAL: separator stops 16 pt short of the right edge | PASS |
| Paused rows | PASS | PASS: grey time, blank time for "Tag release" | PARTIAL: "Every Friday at…" vs "Fridays at…" | PASS | PASS | PASS (pause glyph) | PASS | PASS |
| Closed rows | PASS | PASS | PARTIAL: "· 5 runs" missing | PASS | PASS | PASS | PASS | PASS |
| List footer | — | **FAIL** (extra): the board has no footer | extra copy | — | — | — | — | — |
| Dock + Tasks badge | PASS | PASS | PASS | PASS | PARTIAL: badge is system orange | PARTIAL: icon fill styles swapped | PASS (56 pt, + at right) | PASS: badge = Needs input count across all hosts (3) |

### Task view (`tA2d-detail*`)

| Component / state | Internal consistency | Structure | Copy | Typography | Colour | Glyphs | Spacing |
|---|---|---|---|---|---|---|---|
| Top bar: back + Edit/••• pill | PASS (the morph during the push is transient) | PASS: ••• opens Run now and Stop future runs | — | — | native glass, darker | native SF pencil and ellipsis | PASS |
| Title, schedule, chips | PASS | PASS | data (agent/model, host) | PASS: 28 bold, cap height 20 px on both | PASS: chip `#1C1C1E`, C badge `#D97757` | minor: filled host icon vs outline | PASS: chips 26 pt |
| Card: next run | PASS | PASS | PASS | PASS (12/22/15) | **FAIL**: Run now fill, blue tokens | PARTIAL: play and pause icons about 60% larger | PASS: card 153 vs 154 pt |
| Card: paused | PASS | PASS | PARTIAL: sub-line wording | PASS | PASS: PAUSED amber | PARTIAL (icons) | PASS |
| Card: failed | PASS | PASS | PASS | PASS | PARTIAL: label colour | minor: filled sparkles | **FAIL**: reason wraps at 222 pt |
| Card: retrying | PASS | PASS | PASS | PASS | PASS: green tint | PASS | PASS |
| Card: waiting | PASS | PASS | PASS | PASS | PARTIAL: label colour | PASS | PASS |
| Card: answered | **PARTIAL**: card says "Running again" while the timeline still says "Waiting" | PASS | PASS | PARTIAL: line height 20 vs 23 | PASS | minor: footnote icon "i" vs "!" | PASS |
| Instructions | **FAIL**: "Show more" shows on the failed task although all the text is visible | PARTIAL: 3-line clamp vs 2 on the failed and waiting boards | PASS | **FAIL**: line pitch 19 vs 22 | PASS | — | — |
| Runs header + timeline | PASS (nodes, lines) | **FAIL**: missing Retry tail (next run); extra upcoming rows (retrying); extra Runs section (waiting) | PARTIAL: "skipped" row adds the time; hidden duplicate "no session started" | PASS (15/13) | PARTIAL: accent blue | PASS | PARTIAL: rows 35/55 pt vs 37/59 |
| Ask bar | PASS | PASS | PARTIAL: the placeholder changes on retry | PASS (17) | native glass, darker | minor: filled sparkles vs outline | **FAIL** (whole screen): no bottom fade above the bar |

## Deltas (design vs app, each measured)

### Bugs (no design counterpart needed)
1. **Spurious "Show more" (failed task, instructions).** The app shows all 3 lines of "Audit dependencies … safe patch updates." and still shows "Show more". Tapping it only swaps the label to "Show less": a pixel diff of the instructions area changes only in the button (x 62–97). Crop: `raw/zoom-app-failed-showmore.png`, `view-failed-02-instructions-runs.png`.
2. **The failure reason wraps early (failed card).** Design: the reason runs to x≈317 before it wraps ("…so no session / started."). App: the text frame is 222 pt wide inside a 330 pt card ("…so no / session started."). Crop: `view-failed-01-status-card.png`.
3. **Duplicate copy in the failed timeline body.** The accessibility label reads "Failed · Opus 5.5 was unavailable, so no session started · no session started". On screen it is hidden by truncation; VoiceOver reads it. Design: "Failed · model unavailable · no session".
4. **Answered state contradicts itself for about 8 s.** The card says "RUNNING AGAIN" while the timeline row still says "Today · 9:58 AM · Waiting" (orange). It resolves to Running on the next refresh. The design has no timeline in this state. `raw/app-detail-answered.png`, `raw/app-detail-answered-later.png`.

### Structure
5. **List footer.** Design has none. The app adds "Tasks run while their host is awake and LFG is running." below Closed.
6. **Retrying timeline.** Design: the first row is the live "Today · 10:14 AM · retry · Running" and there are no upcoming rows. App: "Fri, Oct 16 · Next" and "Sat, Oct 17" sit above the running retry. `view-retrying-02-runs.png`.
7. **Waiting state Runs section.** Design: the content ends after Instructions; there is no Runs header or timeline, and the space above the Ask bar is empty. App: adds "Runs · 1 run · 0 completed" and a "Today · 9:58 AM · Waiting" row. `view-input-03-instructions-runs.png`.
8. **Retry tail on an older failed run (next-run state).** Design: "Tue, Oct 13 · 9:00 AM" (failed) has a blue "Retry" tail. App: "Mon, Oct 12" (failed) has no tail. The app adds Retry only when the failed run is the latest. `view-next-05-runs.png`.
9. **Instructions clamp.** Design: 2 lines with no Show more on the failed and waiting boards. App: 3 lines in every state.
10. **Top-bar running count.** Design: "Connected · 1 running". App, with 3 hosts: "3 hosts online" and no running count, although a task is running.

### Spacing and typography
11. **Section header height.** Design 38 pt (padding 14/6). App 52 pt: the label sits about 7 pt lower and the gap to the first row is about 8 pt larger, so each header adds 14 pt. Pixel check: label cap top to previous separator is 18 vs 25; label bottom to the first title is 26 vs 34. `list-02…`, `list-03…`.
12. **Instructions line pitch.** Design 22 pt (16/22). App 19 pt (measured ink rows 438/457/476 vs 433/455/477). `view-next-04-instructions.png`.
13. **Timeline row pitch.** Design 37 pt (upcoming) and 59 pt (past, with body). App 35 and 55 pt, because the 20 pt line box is not applied.
14. **Separator extent.** Design: the hairline runs from x=78 to the screen edge (x=389). App: x=78 to 385 on a 402 pt screen, so it stops 16 pt short.
15. **Status text size.** Design 16 pt semibold. App 14 pt semibold in the multi-host form (cap and ascender height 13 vs 11 px).
16. **Answered card body.** Design line height 23. App about 20.

### Colour tokens
17. **Section count.** Design `#8E8E93` (measured about 142–149). App about `#434343` (max 67,67,67): tertiary label, visibly dimmer.
18. **Run now / Retry now fill.** Design `#0A6EE0` (10,110,224). App `#0091FF` (0,145,255), the system blue: lighter and brighter.
19. **Accent text** (Pause/Resume label, Next, Show more, Open session, sparkles). Design `#409CFF`. App `#0091FF`/`#009AFF`.
20. **Failed card label.** Design `#FF6961`. App about `#FF4548` (system red).
21. **Waiting card label.** Design `#FFB340`. App about `#FF9E34` (system orange). Badge and amber text measure 255,164,66 vs `#FF9F0A`.
22. **Glass surfaces** (back button, pill, dock, Ask bar). Design: `rgba(44,44,46,.92)` (about 40,40,42). App: 25 (toolbar pill and back), 21 (dock), 18 (Ask bar). These are classed as a native Liquid Glass translation, not a fail, but the three app shades also differ from each other.

### Copy (formatter output, same underlying schedule)
23. Row schedule wording: "Weekdays at 9:00 AM" vs "Every weekday at 9:00 AM"; "Daily" vs "Every day"; "Mondays/Fridays at…" vs "Every Monday/Friday at…".
24. Closed finite repeat: "Daily · 5 runs · Pro" vs "Every day · Pro".
25. Failed list row: "Failed · model unavailable" vs "Failed · Opus 5.5 was unavailable, so no se…" (the full error, truncated).
26. Paused card sub-line: "Resume to run again on weekdays at 9:00 AM" vs "…every weekday at 9:00 AM".
27. Skipped row: "Fri, Oct 16 · skipped while paused" vs "Fri, Oct 16 · 9:00 AM · skipped while paused".
28. Retrying Ask bar placeholder: design keeps "Ask why it failed, or change it…". The app switches to "Ask to change this task…".

### Glyphs (minor)
29. Row chevron: 7×12 px vs 5×8; colour about 77 vs `#48484A`.
30. Card button icons: play 12×14 vs 7×8; pause 11×14 vs 8×10.
31. Dock: design has a filled Sessions icon and an outline Tasks icon. The app has an outline Sessions icon and a filled Tasks icon.
32. Ask-bar and Ask-to-fix sparkles are filled (SF) vs outline. The host chip icon is a filled desktop vs an outline monitor. The answered footnote icon is "info.circle" vs an exclamation circle.

### Whole-screen
33. **Bottom fade under the Ask bar.** Design: a 130 pt gradient to 96% black behind the bar fades content near the bottom. App: content 6 pt above the bar renders at about 95% intensity, with no fade (`raw/zoom-app-detail-under-askbar.png`). The list does fade content behind the dock (text there measured at about 45% intensity).

## Non-deltas (excluded on purpose)
- Data: names, hosts (Air vs Pro), agent/model chip text, times, counts ("3 runs · 2 completed"), elapsed times, and the raw error wording from the fixture ("Model unavailable · no session started" comes from the fixture's error text).
- Paused-row order: the app sorts by next run (Fri before Mon). The board's order follows no visible rule.
- Badge = 3 under the Pro filter: the badge counts Needs input across all hosts (All hosts shows Needs input 3), which matches the rule.
- Text about 5% narrower in the app than in Chrome at the same size (cap heights are equal). This is a renderer difference, so line wraps differ.
- iOS 26 native chrome (glass toolbar pill and back button, SF Symbols in the toolbar, scroll-edge dimming under the top bar).

## Carry-overs / unverified
- The single-host header ("Connected · N running") is not reachable with 3 hosts configured. The source shows it renders "N running" in semibold label colour, not regular `#A1A1A6`. This is unverified at runtime.
- Badge hidden at 0: not exercised.
- Content scrolling behind the Ask bar: the task view's content is too short to pass behind the bar, so only the missing fade above the bar is evidenced.
- Hairline colours (separators, timeline lines) cannot be measured at 1x.
- Light mode, and the running and closed task-view states, have no board in scope.
- Side effect: one FlowDeck call without `-S` (a help command) made the session guard create and boot sim `cc-aa2af7c8-abe69521` (D379DCF1-9370-4565-9D99-77FC0C464D1D) and evict the idle sim `cc-01a1387e`. The verification sim was not affected.

## Files
Paired crops (design on top, app below):
- List: `list-01-topbar.png`, `list-02-needs-input-section.png`, `list-03-active-section.png`, `list-04-paused-section.png`, `list-05-closed-section.png`, `list-06-dock.png`
- Next run: `view-next-01-topbar.png` … `view-next-06-askbar.png`
- Paused: `view-paused-01-status-card.png`, `view-paused-02-runs.png`
- Failed: `view-failed-01-status-card.png`, `view-failed-02-instructions-runs.png`, `view-failed-03-header.png`
- Retrying: `view-retrying-01-status-card.png`, `view-retrying-02-runs.png`, `view-retrying-03-askbar.png`
- Waiting: `view-input-01-header.png`, `view-input-02-status-card.png`, `view-input-03-instructions-runs.png`
- Answered: `view-answered-01-card.png`, `view-answered-02-runs.png`
- Full screens side by side: `full-list-top.png`, `full-list-paused-closed.png`, `full-view-{next,paused,failed,retrying,waiting,answered}.png`
- Raw captures: `raw/` (design `*.jpg`, app `*.png`, zooms)
