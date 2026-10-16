# Sessions list (S2) — design verification, round 3

**Verdict: PARTIAL.** Three deltas are confirmed in the parts that could be captured. The lower-list states could not be captured, because the simulator was shut down partway through the run (see "What happened to the simulator").

- Design: `http://127.0.0.1:8793/s2-list.dc.html` (390×844, dark), rendered in Claude in Chrome. Expected values come from the board's DOM and inline styles. The 3x crops were rendered by applying a CSS `scale(3)` transform to the board in my own tab, capturing tiles and stitching them (`design-*@3x.png`).
- App: simulator C47EB72F (iPhone 17 Pro, 402×874), debug fixture, top-of-list state. `app-top.png` is the lossless 1x FlowDeck screenshot. `app-top@3x.png` is a full-resolution frame from a 2 s FlowDeck recording (h264), used for glyph shapes and sizes.
- Tasks badge: `../phase1-list-r2/self-taskbadge.png` (variant fixture). It differs from the r3 app capture only in the Ship meta line and the Tasks badge, so it comes from the same build.
- Coordinates: list content in the app sits +4 pt lower (taller safe area, accepted). Bottom-anchored chrome sits +30 pt lower. Right-anchored items sit +12 pt to the right. All app numbers below are converted back to design coordinates.
- Color note: the 1x app PNG reads about 5% brighter on saturated colors (for example green 50,220,92). The 3x frame reads the tokens exactly (green 46,205,89, amber 252,159,0, purple 188,89,236). So the gain comes from the capture pipeline, not from the tokens.

## Per-component results

| # | Component | Criterion | Result | Design (measured) | App (measured) | Crop |
|---|-----------|-----------|--------|-------------------|----------------|------|
| 1 | Host dots | size | PASS | 8×8 pt | 8×8 pt (24×24 px @3x) | 01-host-dots |
| 1 | Host dots | color | PASS | #30D158 | 46,205,89 @3x | 01 |
| 1 | Host dots | **left inset** | **FAIL** | dot1 x=16, dot2 x=69 | dot1 x=24.0, dot2 x=76.0 | 01 |
| 1 | Host dots | dot→label gap, host spacing, vertical center | PASS | gap 7 px, Pro→dot2 13 px | 8 px, 13 px, center +4 (accepted) | 01 |
| 2 | Header Needs input | chevron / label / count position, color | PASS | label x=42, count x=139, amber #FF9F0A, count #8E8E93 | label x=42, count x=136, same tokens | 02 |
| 2 | Header chevron | size | note (≤1.2 pt) | about 8.1×4.9 pt | 9.3×5.7 pt, same position (x=22) | 16-header-chevron |
| 3 | Header Working | layout, grey label #A1A1A6 | PASS | label 42–100, count 111 | 42–98, count 109 | 03 |
| 4 | Header Unread + Mark all read | layout, blue #409CFF, right inset 16 | PASS | right edge 372 (=390−18) | right edge 384 (=402−18), color 59,154,247 @3x | 04 |
| 5 | Row: question | title / line-2 / meta, dot | PASS | dot x=20 at row+18, bubble 41.7–52.0, text 59.3 | dot x=20 at row+18, bubble 41.7–52.3, text 59.3 | 05 |
| 6 | Row: sign-in | key glyph, text start | PASS | key 41.7–52.0, text 59.7 | 41.7–52.0, text 60.0 | 06 |
| 7 | Row: working | live dot + ring, green line | PASS | dot 40.0–46.7, text 52.7 | 40.0–47.0, text 52.7 | 07 |
| 8 | Row: working + task | **repeat glyph** | **FAIL (minor)** | 9.3 w × 11.3 h pt, text at 59.0 | 11.7 w × 10.0 h pt, text at 61.0 | 08, 15-meta-repeat-glyph |
| 9 | Row: unread | purple dot #BF5AF0, 600 title, #D1D1D6 line | PASS | — | same | 09 |
| — | Meta monitor glyph | size, gap | PASS | 10.7 pt wide | 10.7 pt wide | 05 |
| — | Row metrics | height, separator | PASS | 87 + 0.5 hairline #2C2C2E from x=40 | 87, 2 px @3x of 44,44,44 from x=40 | — |
| — | Internal consistency | background uniform, no seams | PASS | #000 | #000 list; near-black (3,3,3) top fade (accepted) | side-by-side-top |
| 10 | Tab bar: Tasks | glyph, label, white | PASS | glyph 17.4×16.7 pt, label y 795.7 | 17.4×16.7 pt, label y 796.0 | 14-tab-tasks-glyph |
| 10 | Tab bar: Sessions tint | #409CFF | PASS | 65,156,255 | 62,153,253 | 10 |
| 10 | Tab bar: **Sessions glyph** | shape and size | **FAIL** | 22.0×17.3 pt; LEFT bubble in front, right bubble behind with a cut-out | 27.0×21.7 pt; RIGHT bubble in front (cut-out on the right bubble) | 13-tab-sessions-glyph |
| 10 | Tab bar: **Sessions label** | baseline | **FAIL** (from the glyph) | y 795.3, level with Tasks (795.7) | y 798.7, 2.7 pt below Tasks (796.0) | 10 |
| 10 | Sessions badge | position, size, color | PASS | x 75–92.7, top 768, 18 pt, #FF9F0A | x 74–91.7, top 768, 18 pt | 13 |
| 10 | Tasks badge (variant) | position, size, color | PASS | x 161–178, top 768 | x 162–179, top 768 | 17-tasks-badge-variant |
| 11 | Plus button | glyph size, position | PASS | plus 14.3 pt, button x=314 (right 20) | 14.3 pt, x=326 (=402−20−56) | 11 |
| 12 | Toolbar capsule | — | accepted (native) | 48 h | native glass | 12 |

The text in app titles is about 6% narrower (for example "Ship lfg…" is 199 px vs 211 px). This is SF Pro's native optical tracking at 17 pt, which Chrome does not apply. It is not counted as a delta.

## Deltas (priority order)

1. **Sessions tab glyph:** design 22.0×17.3 pt custom double bubble with the left bubble in front, vs app 27.0×21.7 pt double bubble with the right bubble in front (looks like SF `bubble.left.and.bubble.right.fill`). Because the glyph is taller, the Sessions label sits 3.4 pt lower than the design and 2.7 pt lower than the Tasks label. In the design the two labels are level.
2. **Host-dot cluster inset:** design left 16 pt vs app 24 pt (the whole "● Pro ● Air" group is about 8 pt further right). Size, color and spacing match.
3. **Meta repeat glyph:** design 9.3×11.3 pt vs app 11.7×10.0 pt (wider and flatter). The text after it starts at 61.0 vs 59.0.
4. Note only: the header chevron is about 1.2 pt wider than the design.

## Not verified (no app capture possible)

These have design captures ready (`crops/U1…U5`, `design-folded@3x.png`, `design-idle-closed@3x.png`), but no app capture:

- Unread + task row ("Daily repo review"). In the app it is only visible half-faded under the dock.
- Folded Idle and Closed headers, and the folded Needs input / Working state.
- Idle row (blue dot, "Ready for your next message").
- Closed row (grey dot; no host, which is accepted).
- "Load more" row: blue under an expanded Closed group, absent when Closed is folded.
- Bottom of the list.

The r2 captures of these states cannot stand in. `SessionListView.swift` and `RootView.swift` changed at 14:47–14:48, after the r2 app captures (14:31–14:43), and r2 `app-top.png` differs from r3 `app-top.png` in 11 places.

## What happened to the simulator

- About 14:51: my first FlowDeck call (`screen --help`) left out `-S`. The session guard then created and booted an extra simulator, `cc-68284ba9-aef62f1e` (5AFF594E). While doing so it evicted another session's idle simulator, `cc-aa2af7c8-abe69521`.
- Between about 14:54 and 15:05 I worked only on the design side and sent no commands to C47EB72F.
- About 15:05: another session's guard reached the booted-simulator cap and evicted the most idle simulators. Its log line reads "evicting idle simulator 'cc-68284ba9' (idle 10m [ledger], cap 4 …)". The extra simulator I had created was evicted in the same pass.
- At 15:06 my first swipe returned "Simulator … is not booted".
- I did not boot or relaunch anything, as instructed. I never changed the app state: the swipe failed and no header was toggled.

## Files

- `design-board.png`, `design-board@3x.png` — board in its default state
- `design-folded-needs-working.png`, `design-folded@3x.png` — Needs input and Working folded, so Idle and Closed headers are in view
- `design-idle-closed-expanded.png`, `design-idle-closed@3x.png` — Idle and Closed expanded
- `app-top.png` (1x, lossless), `app-top@3x.png` (frame from the recording)
- `side-by-side-top.png`
- `crops/01…17` — paired crops (design on top, app below); `crops/U1…U5` — design only
