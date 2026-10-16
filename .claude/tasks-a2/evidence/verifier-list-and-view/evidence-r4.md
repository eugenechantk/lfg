# Verifier evidence, round 4: Tasks list + task view vs A2 dark boards

Date: 2026-10-15 17:45–17:55 HKT · Verifier: claude-design-verifier (independent) · Verdict: **PASS**. The three round-3 colour deltas are resolved. What remains is minor and does not change the verdict.

Earlier rounds: `evidence.md`, `evidence-r2.md`, `evidence-r3.md`.

## Scope and setup
- Boards: `tA2d-list`, `tA2d-detail` (+ paused), `tA2d-detail-failed` (+ retrying), `tA2d-detail-input` (+ answered). Board files are unchanged since 13:22, so the Chrome renders in `raw/design-*.jpg` remain the reference.
- App build: the binary on sim `1D902A87-…` is from 17:42:53. It is newer than every Tasks source edit; the latest is `TaskEditorViews.swift` at 17:42:03. 1x captures are in `raw-r4/`. Every FlowDeck call passed `-S`.
- Full pass:
  - List with the Pro filter: top, bottom, and Closed, which started collapsed after the relaunch and was then expanded.
  - Task view in all six states: next run, paused (then Resume; host shows `enabled: true, pausedAt: null`), failed, retrying, waiting, answered.
- I diffed each capture against the round-3 capture of the same state. That isolates what this build changed:
  - List and Closed rows: only the section-header chevrons changed, plus data (the running row's elapsed and start times).
  - Next run: only the countdown text changed.
  - Paused and answered: no pixel changes.
  - Retrying: only the two start times changed.
  - Failed: only the x-icon colour changed. Its red channel stayed at 255, so the luminance diff stayed under the threshold. I measured it directly.
- The fixture host was reset after Retry and Answer. It is now PID 42876.

## Per-component table

| Component / state | Consistency | Structure | Copy | Type | Colour | Glyphs | Spacing |
|---|---|---|---|---|---|---|---|
| Section headers | PASS | PASS (Closed starts collapsed) | PASS | PASS | **PASS**: chevron uses the label's `.secondary` (peak 121 at 1x vs board 171; same token as the label, which measures 157 vs 167) | minor: thinner stroke | PASS (38 pt) |
| Rows | PASS | PASS | PASS | PASS | PASS (system tones: "10:00" 255,156,51; "2:00" 255,71,75) | PASS (chevron 5×9) | PASS (separator to x=401) |
| Paused rows | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| Closed rows | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| Dock + badge | PASS | PASS | PASS | PASS | PASS | minor: filled Tasks icon | PASS |
| Task view top bar | PASS | PASS | — | — | native | native | PASS |
| Title, schedule, chips | PASS | PASS | PASS ("Every weekday at 9:00 AM") | PASS | PASS | PASS | PASS |
| Card: next run | PASS | PASS | PASS | PASS | PASS (Run now 10,110,224 = `#0A6EE0`) | PASS | PASS |
| Card: paused | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| Card: failed | PASS | PASS | PASS | PASS | **PASS**: x icon now (255,68,71) system red; label `#FF6961`; tint 43,11,12 | PASS | PASS |
| Card: retrying | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| Card: waiting | PASS | PASS | PASS | PASS | **PASS**: dot now (255,146,48) system orange; label `#FFB340` | PASS | PASS (context line pitch 21 vs 20) |
| Card: answered | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| Instructions | PASS | PASS (2 lines with no button in failed, retrying, waiting) | PASS | PASS (pitch 22) | PASS | — | PASS |
| Runs header + timeline | PASS | PASS | minor: full error text | PASS | PASS | PASS | PASS (37/59) |
| Ask bar + bottom fade | PASS | PASS | PASS | PASS | native glass | minor: filled sparkles | PASS |

## Resolved since round 3
1. Section-header chevron: max brightness about 61 → about 121. It now uses the same `.secondary` token as the "Active" label. The remaining gap to the board (171) comes from the thin 7×5 glyph at 1x, not from the colour.
2. Waiting card dot: (255,179,64) → (255,146,48), system orange like the rest of the board's amber.
3. Failed card x icon: (255,109,101) → (255,68,71), system red.

## Minor, not counted
- Failed result text in the list and timeline is the full error sentence ("Failed · Opus 5.5 was unavailable, so no sessio…"). The board has "Failed · model unavailable". The text comes from the fixture's raw error.
- Filled SF symbols where the board uses outlines: the Tasks dock icon and the sparkles.
- Low confidence at 1x: the schedule line and the "by next run" hint (about 129–137) are a little darker than `#A1A1A6`.

## Files
- Pairs: `r4-list-01-needs-input.png`, `r4-list-02-active.png`, `r4-list-03-dock.png`, `r4-list-04-paused.png`, `r4-list-05-closed.png`, `r4-list-06-header-chevrons.png`, `r4-next-01…06`, `r4-paused-01/02`, `r4-failed-01/02/03`, `r4-retrying-01/02/03`, `r4-waiting-01/02/03`, `r4-answered-01-card.png`
- Full screens: `r4-full-list-top.png`, `r4-full-list-paused-closed.png`, `r4-full-view-{next,paused,failed,retrying,waiting,answered}.png`
- Raw: `raw-r4/`
