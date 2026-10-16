# Sessions list (phone) vs board `s2-list` — verification round 4

**Verdict: PARTIAL.** Rows, group headers, the dock, the badges and the plus button match the board to within about 1pt. One component is off: the Search/More capsule is shorter and wider than the board, and its glyphs are about 34% bigger. It is a native iOS 26 toolbar group, so the system sets its size. The product owner needs to decide whether that is acceptable. One question is still open: the board shows the time "9:00 AM" on the task row, and the app can only show relative times.

## Scope and method

- **Design:** `http://127.0.0.1:8793/s2-list.dc.html`, rendered in Chrome. The 390×844 artboard was scaled 3x with a CSS transform, captured in six tiles and stitched together, so it matches the app's 3x frames pixel for pixel. Geometry and tokens were also read from the DOM (`getBoundingClientRect`, computed styles).
  - Default state (Idle and Closed folded): `design-default@3x.png`
  - Needs input folded, so the folded Idle and Closed headers sit above the dock: `design-needsfolded@3x.png`
  - Needs input and Working folded, Idle and Closed expanded: `design-idleclosed-open@3x.png`
  - The design's folded Idle and Closed headers fall under the dock in its default state, because the board has no bottom inset. That is why the extra states were needed.
- **App:** iPhone 17 Pro simulator `C47EB72F-…`, fixture `LFG_S2_LIST_FIXTURE=1` (plus the `taskbadge` variant). Frames were taken with `flowdeck … record` and ffmpeg's last frame, at 1206×2622 (3x).
- **How each component was compared:** the same Python pixel tools ran on both 3x frames (bounding boxes, run-lengths, peak colors). See the scratchpad scripts `meas.py`, `structure.py`, `hruns.py` and `colors.py`.
- **Device offset:** the app's header row is centered at y=84 and the board's at y=80, because the iPhone 17 Pro nav bar is lower. Everything below is compared relative to that offset. The offset itself is not a delta.

## Per-component table

| # | Component / state | Criterion | Result | Design (measured) | App (measured) |
|---|---|---|---|---|---|
| 1 | Host dots "● Pro ● Air" | Structure, color, type | PASS | 8pt dots at x16 and x68.8, #30D158; 16/600 white labels | 8pt dots at x16 and x68, (48,209,88); "Pro" ink 31.3–55.3, "Air" 82.7–103.3 |
| 2 | Search/More capsule | Size | **DELTA** | 98 × 49–50pt (48 plus a 0.5pt border) | 101.7 × 44.0pt (sharp glass rim at y62 and y106) |
| 2 | Search/More capsule | Glyph size | **DELTA** | Magnifier 15.7×15.7pt; ••• 14.7pt wide, dots 3.3pt | Magnifier 21.0×21.0pt; ••• 19.7pt wide, dots 4.0pt |
| 2 | Search/More capsule | Glyph inset | DELTA (follows from the size) | Magnifier center 27.8pt from left edge; ••• center 27.0pt from right edge | 23.8pt and 23.2pt |
| 2 | Search/More capsule | Material | Accepted | rgba(44,44,46,.92) flat fill | System glass, (24,24,24) |
| 3 | Group headers, expanded (Needs input / Working / Unread) | Layout, copy, color | PASS | Chevron x22.3, label x42.3, 15pt; amber / #A1A1A6 label, #8E8E93 count | Same x positions; amber (244,152,8), grey 160, count 140 |
| 3 | Group headers, expanded | Chevron size | Minor delta | 8.33 × 5.0pt | 9.33 × 5.67pt (about 25% more ink); same color #A1A1A6 |
| 4 | Folded Idle / Closed headers | Pitch, chevron | PASS (chevron minor) | Separator→label +18, header pitch 38; right chevron 5.0 × 8.34 | +18, pitch 38; right chevron 5.67 × 9.34 |
| 5 | Needs input rows (question, sign-in) | Structure, glyphs, copy, color | PASS | Dot 8pt at x20; title x41; ask/key glyph 41.7–52.3; line text at 59.7 / 60.0; amber line | Identical to 0.3pt; ask/key glyph 41.7–52.3; text 59.7 / 60.0 |
| 6 | Working rows (incl. scheduled task) | Live dot, repeat glyph | PASS | Core 7pt, ring 13pt; "Working" text at x52.7; repeat glyph 41.7–51.3, text at 59.0 | Core 7pt, ring 12.67pt; text 52.7; repeat 41.7–51.3, text 59.0 |
| 7 | Unread rows + "Mark all read" | Weight, color, action | PASS | Title 600; line #D1D1D6; action #409CFF, right margin 17.33 | Line (208,208,208); action (60,152,252), right margin 17.33 |
| 8 | "Daily repo review" (unread + task) | Structure | PASS | Repeat glyph, then "lfg · Opus 5.5 · 9:00 AM · [monitor] Pro" | Repeat glyph, then "lfg · Opus 5.5 · 5h · [monitor] Pro" |
| 8 | "Daily repo review" | Time format | **OPEN** | Clock time "9:00 AM" | "5h". `compactDuration` is relative only, so a clock time can never render |
| 9 | Idle row (expanded) | All | PASS | Dot #0A84FF; separator→dot 57 | (8,131,249); 56.67 |
| 10 | Closed row (expanded) | All | PASS | Dot #636366; copy "Ended yesterday · send a message to resume" | (98,98,98); same copy; no host (accepted) |
| 11 | "Load more" | Present when Closed is expanded, absent when folded | PASS (accepted extra) | n/a | Shows "Loading more" with a spinner briefly, then "Load more". Gone after refolding |
| 12 | Row separators | Inset, color | PASS | x40 to the edge, (44,44,47), 0.5pt | x40 to the edge, (39–44 grey), 0.67pt |
| 13 | Row pitch | Rhythm | PASS | 88.0pt | 87.67pt (−0.33 per row) |
| 14 | Dock pill | Geometry | PASS | x20, 186×56, bottom gap 28 | x20, 184×56, bottom gap 28 |
| 14 | Dock selected tab | Geometry | PASS | 88×48 at pill +5/+4 | about 88×48.5 at pill +4/+4 |
| 14 | Dock selected tab | Fill | Minor delta | #3A3A3C solid (lum 58) on a lum-34 pill | `Color.primary.opacity(0.07)` (lum 34) on a lum-17 glass pill. Lower contrast |
| 15 | Tab glyphs and labels | Glyph, type | PASS | Sessions 22.3×17.7 blue; Tasks 18×17; labels 10/600 | 22.3×17.3; 18×17; label boxes within 0.7pt |
| 16 | Sessions badge | Badge | PASS | 18×18 amber at pill +55/+8, dark numeral | 18×18 at pill +54/+8 |
| 17 | Tasks badge | Badge (taskbadge variant) | PASS | 18×18 at pill +141/+8 | "1", 18×18 at pill +142/+8. The default fixture has no badge, which is a data difference |
| 18 | Plus button | Geometry, glyph | PASS | 56×56, right 20, bottom 28, glyph 14.67 | 56×56, right 20, bottom 28, glyph 14.67 |
| 19 | Internal uniformity | Background, seams | PASS | n/a | Gutter x8, mid x330 and edge x396 columns are pure black (lum ≤ 4) from y110 to y780 in two scroll states. No banding or row-background seams |
| 20 | Whole screen: header pinned while scrolling | Fixed-on-scroll | PASS | Header is absolutely positioned | Host dots stay at y84 across 6 scroll positions; list content fades under the header (accepted) |
| 21 | Whole screen: content under the dock | Glass and fade | PASS (accepted) | 150pt gradient | Row text visibly passes under the dock glass |

## Deltas (design value vs app value)

1. **Capsule size:** design 98 × 49–50pt, app 101.7 × 44.0pt. This comes from two native `.primaryAction` `ToolbarItem`s that iOS groups into one glass capsule (`SessionListView.swift:758–769`).
2. **Capsule glyph size:** magnifier 15.7pt in the design vs 21.0pt in the app; ••• 14.7×3.3pt vs 19.7×4.0pt. These are default SF Symbol sizes in the toolbar. Insets are 27.8/27.0pt in the design vs 23.8/23.2pt in the app.
3. **Group chevrons, minor:** down 8.33×5.0pt vs 9.33×5.67pt; right 5.0×8.34pt vs 5.67×9.34pt. Same color. About 1pt bigger and heavier.
4. **Selected dock tab fill, minor:** #3A3A3C on the board vs 7% primary on glass in the app (lum 34 vs 58). The tab still reads as selected, with less contrast.
5. **Open question: task-row time.** The board shows "9:00 AM" on "Daily repo review". The app's formatter is relative only ("45s/3m/2h/1d/3w"), and the fixture uses `agoMin: 300`, which prints "5h". The board itself mixes relative and clock times with no stated rule, and the feature doc says only "time". The owner needs to decide whether task rows (or older rows) should show a clock time.

## Not deltas

- **Data differences:** group counts (Unread 15/3, Idle 17/1, Closed 40/1); the Tasks badge count; Unread row order (the fixture gives Daily and Enhance the same 5h, so Daily sorts last).
- **Accepted by the owner:** glass materials, no host on closed rows, scroll-edge fades, raw model names, "Load more", SF text width.
- **Transient live state:** around 15:20–15:22 the Pro host showed a grey dot and grey label (`crop-header-refold.png`, `app-taskbadge.png`). By 15:41 it was green again (`crops/header-final-app.png`). Host reachability is live client state, and the board has no offline state.

## Unverified

- Press and highlight states, the fold/unfold animation, and the "Mark all read" action. These are behavior, not in the visual scope.
- The Tasks badge counting failed task runs. The feature doc says that is deferred.

## Files

- **App frames:** `app-top.png`, `app-bottom-folded.png`, `app-idle-open.png`, `app-closed-open.png` (Loading more), `app-closed-open-2.png` (Load more), `app-closed-refold.png`, `app-taskbadge.png`, `app-top-final.png`
- **Design frames:** `design-default@3x.png`, `design-needsfolded@3x.png`, `design-idleclosed-open@3x.png`, `design-top.png` (1x)
- **Paired crops** in `crops/` (each has `-design.png` and `-app.png` halves): `header.png`, `needs-input.png`, `working.png`, `unread.png`, `folded-headers.png`, `idle-closed-open.png`, `dock-default.png`, `dock-taskbadge.png`, plus `header-final-app.png` and `../crop-pager-2.png`
