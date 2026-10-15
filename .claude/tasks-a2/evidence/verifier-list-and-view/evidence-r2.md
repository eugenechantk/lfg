# Verifier evidence, round 2: Tasks list + task view vs A2 dark boards

Date: 2026-10-15 (round 2, after the rebuild) · Verifier: claude-design-verifier (independent) · Verdict: **FAIL** (3 open items; everything else now matches)

Round 1 report: `evidence.md` in this folder.

## Scope and setup
- Boards: `tA2d-list`, `tA2d-detail` (+ paused), `tA2d-detail-failed` (+ retrying), `tA2d-detail-input` (+ answered). The board files and `support.js` are unchanged since 13:22 (mtime checked), so the round-1 Chrome renders in `raw/design-*.jpg` are still the ground truth. Design token values come from the board markup.
- App: rebuilt build on sim `1D902A87-…` (iPhone 17 Pro, dark), FlowDeck 1x captures in `raw-r2/`. Every FlowDeck call passed `-S`.
- Full pass, not just the round-1 deltas: list (All hosts and the Pro filter, top, bottom, Closed expanded), task view in every state (waiting, answered, next run, paused, failed, retrying).
- Excluded at the coordinator's direction: the shared top status bar ("N hosts online"). Wraps that come from iOS avoiding a one-word last line count as native typesetting.
- Fixture host reset twice (after answering, after Retry). It is now PID 71009, log `fixture-verifier.log` in the session scratchpad. The list filter is back to All hosts and the list is at the top.

## Per-component table

| Component / state | Consistency | Structure | Copy | Type | Colour | Glyphs | Spacing |
|---|---|---|---|---|---|---|---|
| Section headers | PASS | PASS | PASS | PASS | PASS (count ~0.83 of label vs 0.89 on the board, within 1x tolerance) | minor: chevron 11×7 vs 8×5 | **PASS: 38 pt** (label cap 17 px below the header top on both) |
| Rows: time, title, schedule, result, chevron | PASS | PASS | PASS: "Daily", "Weekdays at 9:00 AM", "Fridays at…", "Daily · 5 runs" | PASS (87 pt rows) | **FAIL**: amber and red tokens | PASS: chevron 5×9 `#48484A`-ish | **PASS**: separator x 78→401 |
| Paused rows | PASS | PASS | PASS | PASS | PASS (grey times) | PASS | PASS |
| Closed rows | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| End of list | PASS: footer gone | PASS | — | — | — | — | PASS |
| Dock + badge | PASS | PASS | PASS | PASS | **FAIL**: badge `#FFB340` vs `#FF9F0A`; Tasks label `#409CFF` PASS | minor: Tasks icon filled vs outline (Sessions icon now matches) | PASS |
| Task view top bar | PASS | PASS | — | — | native glass | native SF symbols | PASS |
| Title, schedule, chips | PASS | PASS | **FAIL**: schedule line | PASS | PASS | PASS (outline display icon) | PASS |
| Card: next run | PASS | PASS | PASS | PASS | PASS: Run now `#0A6EE0`, Pause `#409CFF` | PASS: play 9×9, pause 7×10 | PASS |
| Card: paused | PASS | PASS | PASS: "on weekdays at 9:00 AM" | PASS | PARTIAL: PAUSED `#FFB340` vs `#FF9F0A` | PASS | PASS |
| Card: failed | PASS | PASS | PASS | PASS | PASS: label `#FF6961`, Retry now `#0A6EE0`; minor: x icon and tint from `#FF6961` instead of `#FF453A` | PASS | PASS (the reason wrap is iOS orphan avoidance, see notes) |
| Card: retrying | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| Card: waiting | PASS | PASS | PASS | PASS | PASS: label `#FFB340`; minor: dot `#FFB340` vs `#FF9F0A` | PASS | PASS |
| Card: answered | PASS (no timeline, nothing contradicts the card) | PASS | PASS | PASS (line pitch 23 = 23) | PASS | PASS: footnote "!" icon | PASS |
| Instructions | **FAIL in retrying**: spurious Show more | PASS in next, failed, waiting, answered; **FAIL in retrying** | PASS | PASS: pitch 22 = 22 | PASS (Show more `#409CFF`) | — | PASS |
| Runs header + timeline | PASS | PASS: Retry tail on the older failed run; retrying shows only the live row; no Runs in waiting/answered | PARTIAL: failed body uses the full error | PASS | **FAIL**: failed node and body `#FF6961` vs `#FF453A` | PASS | PASS: rows 37/59 = 37/59 |
| Ask bar + bottom fade | PASS | PASS: placeholder kept while retrying | PASS | PASS | native glass (Ask bar 19, pill 25) | minor: filled 3-star sparkles vs outline | PASS: content fades behind the bar now |

## Open deltas (design vs app)

1. **Spurious "Show more" in the retrying state** (bug). After Retry now, the instructions go back to a 3-line clamp. All of "Audit dependencies … safe patch updates." is visible, and "Show more" still shows. Tapping it changes only the word more→less: the pixel diff of the instructions area is limited to x 62–97 of the button row. The board keeps the 2-line clamp with no button in this state. In the failed state itself this is fixed (2 lines, no button). Crops: `r2-retrying-02-instructions-runs.png`, `raw-r2/zoom-app-retrying-showmore.png`.
2. **Amber and red tokens.** The app now uses one warning token `#FFB340` and one danger token `#FF6961` everywhere. The boards use those only for the waiting and failed card labels. Everywhere else they use `#FF9F0A` and `#FF453A`. Measured in the app (round 1 values in brackets, from system colours):
   - Badge fill (255,179,64) vs `#FF9F0A` [round 1: 255,164,66].
   - List "10:00" and "Needs input" label and ask result ≈ (255,195–202,70) vs `#FF9F0A` [255,164,54].
   - List "2:00" and failed result ≈ (255,107–113,100) vs `#FF453A` [251,67,70].
   - Timeline failed node (255,105,97), exactly `#FF6961`, vs `#FF453A` [255,66,69]. Failed body text the same.
   - PAUSED card label and waiting dot (255,179,64) vs `#FF9F0A`.
   - Failed-card x icon (255,109,100) vs `#FF453A`; card tint (43,18,16) vs board (41,11,9).

   Crops: `r2-list-01-needs-input.png`, `r2-failed-02-instructions-runs.png`, `r2-glyphs-host-dock-sparkle.png`.
3. **Task view schedule line.** Design "Every weekday at 9:00 AM" vs app "Weekdays at 9:00 AM". The list's short form now also feeds the task-view header; the board uses the long form there and the short form only in list rows. Daily ("Every day at 2:00 AM") and Once match. Crop: `r2-next-02-header-chips.png`.

### Minor (do not change the verdict on their own)
- Failed result copy in the list and timeline: design "Failed · model unavailable" / "…· no session" vs app "Failed · Opus 5.5 was unavailable, so no sessio…" (the full error sentence, truncated). The duplicate "no session started" from round 1 is gone.
- Section header chevron: 11×7 px, max grey 132, vs 8×5 px `#A1A1A6`.
- Dock Tasks icon is a filled calendar vs an outline calendar with a clock. The Ask-bar sparkle is the filled 3-star SF symbol vs a 2-star outline.
- Low confidence at 1x: the schedule line and the "by next run" hint use the hierarchical `.secondary` (neutral, core 129–137). Result lines measure 153 with a blue tint. The board uses `#A1A1A6` for all three, so these two lines may sit slightly darker. This was already present in round 1.

## Confirmed fixed since round 1 (re-measured, not taken from the prompt)
- Section headers 38 pt (was 52). Separator reaches the right edge (x 401). Row chevron 5×9 px. List footer removed. Schedule wording in rows is "Daily", "Weekdays at…", "Fridays at…", "Mondays at…", "Daily · 5 runs".
- Section count is about the board's grey (was about `#434343`). Dock Sessions icon is filled. Tasks tab label is `#409CFF`.
- Run now / Retry now fill is exactly (10,110,224) = `#0A6EE0`. Pause/Resume/Next/Show more/Open session are about `#409CFF` (65,160,255). Card button icons are about the board size.
- Instructions line pitch is 22 (438/460/482). 2-line clamp with no button on failed, waiting and answered.
- Timeline rows are 37 and 59 pt. The Retry tail shows on the older failed run (next-run state). Retrying shows only the live "Today · 4:01 PM · retry · Running" row on top. Waiting and answered have no Runs section. Paused shows "Fri, Oct 16 · skipped while paused".
- Failed timeline body no longer repeats "no session started". The answered card no longer conflicts with a "Waiting" row. The Ask-bar placeholder stays "Ask why it failed, or change it…" while retrying.
- Paused card: "Resume to run again on weekdays at 9:00 AM". Answered card body line pitch is 23. Footnote icon is "!".
- A bottom fade now dims content behind the Ask bar: the "Mon, Oct 12" row fades under it in the next-run state.

## Notes and non-deltas
- **Failure reason wrap.** The reason's text frame is 222 pt wide inside a 330 pt card. Filling the width would leave "started." alone on the last line. Elsewhere the card text does use the full width: the waiting card's context wraps at about 350 px. So the early wrap is iOS orphan avoidance, which counts as native typesetting.
- Data: names, hosts (Air vs Pro), agent and model chip text, times and counts. "Weekly · Air" vs "Tuesdays at 10:00 AM · Pro" on Competitor pricing scan is not counted: the board itself writes a weekly schedule as "Mondays at 8:00 AM" on another row, so the board gives no single rule.
- Paused-row order (by next run) and the badge counting all hosts (3) are unchanged non-deltas.
- Not a board state: after the answer lands, the fixture turns the run into "RUNNING NOW · Started 9:58 AM", and the Runs section comes back with a Running row. The card and timeline agree.

## Carry-overs / unverified
- 1x captures only. Thin-line colours and small-text greys are approximate; tokens for large fills are exact.
- Badge hidden at 0 was not exercised.
- Another process took a FlowDeck snapshot on a different simulator during this run ("Last UI snapshot was taken on a different simulator"). My captures on `1D902A87` were unaffected: every screen was re-read before use.

## Files
- Pairs (design on top, app below): `r2-list-00-full-upper.png`, `r2-list-01-needs-input.png`, `r2-list-02-active.png`, `r2-list-03-dock.png`, `r2-list-04-paused.png`, `r2-list-05-closed.png`, `r2-next-01…06`, `r2-paused-01/02`, `r2-failed-01/02/03`, `r2-retrying-01/02/03`, `r2-waiting-01/02/03`, `r2-answered-01-card.png`, `r2-glyphs-host-dock-sparkle.png`
- Full screens: `r2-full-list-top.png`, `r2-full-list-paused-closed.png`, `r2-full-view-{next,paused,failed,retrying,waiting,answered}.png`
- Raw app captures: `raw-r2/`
