# Task view Runs section and model chips: visual design verification (phone and Mac)

**Verdict: FAIL.** The layout is very close. The phone geometry matches the board to within 0.33pt. Ten measured deltas remain. Most are colour tokens; there are also two Mac geometry deltas, one dash-style delta and one scroll-end issue. Each finding below gives the board value, the app value and the evidence.

## Contents
1. Scope, references and method
2. Coverage matrix
3. Findings (numbered deltas)
4. Observations (not counted against the verdict)
5. Whole-screen and interaction checks
6. Coverage gaps
7. Files
8. Timing and tool recovery

## 1. Scope, references and method

**Scope (live, not static-only).**
- Phone task view, Runs section, in three states: folded, upcoming group opened, and past group opened once. This covers the toggle rows, the rail and the run rows.
- The phone model chips for Claude Code and Codex.
- Mac task view, Runs section, folded. The Mac model chips for Claude Code and Codex.

**References (HTML, rendered in Chrome via Claude in Chrome, served from 127.0.0.1:8931).**

| Board | SHA-256 | Viewport |
|---|---|---|
| `tA2d-runs-rail.dc.html` (phone folded) | e4c356460118ad08a18c45fd30fe2bc3a7bb2a8b8a544ab3c42734529540ea03 | 390×1000 |
| `tA2d-runs-rail-open.dc.html` (phone, both groups opened once) | 97aa8b2f3acbe40ce82698588e26fbe8e562aa6da0e786a5bcba9d9dda22de63 | 390×1760 |
| `dA2-runs-rail.dc.html` (Mac folded) | 1619dce27c757ea5971aaadad4e703d97f728ee904d1e2c8a880ca118846b130 | 400×1000 |
| `tA2d-model-pill.dc.html` (chips) | 64e08c4751f12c3738bc8c5055f17853cf82405e86439652f69ba7876e3e131d | 560×300 |
| `support.js` runtime | 3f160299989dc595cf434dac7b7f3e6fd20ed015a2d99e075c3eac09dffe0f10 | — |
| `agent-claude.svg` / `agent-codex.svg` | 56de52962fdc4fb97fd374500b8c3f00df075ef1d0e57f968696f6cdff3b5f63 / 5a0491823a4f3b667e75f55ed21ad5211ae014111d368cca1577ce814fb97533 | — |

- **Rendering:** device pixel ratio 1, CSS zoom 3 on the root, and native region captures from the zoom action (PNG, no profile, treated as sRGB). Fonts reported `loaded` and the SVG logos were complete.
- **DOM:** rects and computed styles were read once per board, inside the board root.
- **Mapping:** the phone folded board maps to the app's folded state. The open board's top half (Show less + 10 upcoming) maps to the "upcoming opened" state. Its past half (12 past + "Show more · 11 earlier") maps to the "past opened once" state. The app matches the board's counts exactly (10 upcoming, 23 past, 12 shown after one tap, 11 left).
- **The open board's bottom toggle is hidden under its own ask bar** (rows 1686–1730, ask bar 1680–1732). For the opened past toggle, I used the DOM (chevron down, dashed rail above and below, "11 earlier") and the folded board's identical toggle template for pixels.

**Implementation.**
- **Phone:** simulator 1D902A87-40EB-40AF-87A6-BBC19508900B (iPhone 17 Pro, dark), with the app as found installed and running (not rebuilt). Repo HEAD is 658dae7, and the working tree is dirty in `shared/Tasks/TaskDetailViews.swift` and related files. The installed build's exact revision is unknown.
- **Phone tasks:** "V long history" on the Pro stand-in (id …045), "Readwise sync check" on Pro (…007, Codex), and "Nightly dependency audit" on Pro (…003, model id `opus`).
- **Mac:** `mac_shot.sh build` at 23:20:45 from the working tree, then `shot --task 45 --height 1000`, `--task 07` and `--task 03` against 8932. Raw shots carry the "Mi monitor" profile. They were converted to sRGB (`app/srgb/`), and every Mac colour below is sRGB.
- **Hosts:** I made no host state changes. Only UI toggles were used.

**Capture method and limits.**
- **Phone geometry:** 3x frames from `flowdeck ui simulator record` (H.264, 1206×2622).
- **Phone colour:** 1x FlowDeck PNGs (402×874). A 3x plateau reading was used when a 1x glyph is too thin. Calibration between the 3x frame and the 1x PNG / board:
  - body text 209 vs 209
  - green (47,208,87) vs (48,209,88)
  - toggle disc 28 vs 28
  - chip fill 25 (3x) vs 28 (1x)
  - So 3x frames read 0–3 levels dark. The 20-level deltas below are far outside that.
- **Mac is 1x only.** `--window-shot` uses `cacheDisplay` at the window's backing scale, and the harness has no scale option. Mac glyph-level details (chevron size, corner radii, dash lengths) are therefore ±0.5–1pt. The board side is measured at 3x.
- **Alignment:** app crops were aligned to the board using the first rail dash (phone offset 98.33pt), the Show-less disc (394.33pt) and the failed-row node (543.0pt).
- **Data ignored:** names, dates, summaries, counts, durations and model names.

## 2. Coverage matrix

Legend: P = PASS, F# = finding number, O# = observation, ~ = PARTIAL (resolution limit), N/A = not applicable.

Criteria: 1 Internal consistency · 2 Structure/layout · 3 Copy · 4 Typography · 5 Colour/tokens · 6 Glyphs · 7 Spacing/shape · 8 States · 9 Nav chrome

| # | Component / state | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Phone · Runs header row (all states) | P | P | P (data) | P | **F1** | N/A | P | P | N/A |
| 2 | Phone · upcoming toggle, folded ("Show more · 8 later") | P | P | P | P | **F1** (count) | P | **F3** (dash) | P | N/A |
| 3 | Phone · upcoming toggle, opened ("Show less", no count, no rail above) | P | P | P | P | P | P (chevron down) | **F3** | P | N/A |
| 4 | Phone · upcoming run rows (2 folded, 10 opened) | P | P | O5 | P | **F1** | P (hollow ring) | P | P | N/A |
| 5 | Phone · past run rows, completed (folded 2, opened 12) | P | P | P | P | P | P | P | P | N/A |
| 6 | Phone · past run row, failed (opened) | P | P | data | P | **F10** (minor) | P | P | P | N/A |
| 7 | Phone · past toggle, folded ("21 earlier") and opened once ("11 earlier") | P | P | P | P | **F1** (count), **F4** (faded at rest) | P | **F3** | P | N/A |
| 8 | Phone · rail (continuity, toggle stubs, upcoming→past join) | P | P | N/A | N/A | **F2** | P | **F3** | P | N/A |
| 9 | Phone · model chip, Claude Code ("Claude default"; also id `opus`) | P | P | O1 | P | P | P | P | N/A | N/A |
| 10 | Phone · model chip, Codex ("Codex default") | P | P | P | P | P | P | P | N/A | N/A |
| 11 | Mac · Runs header row | P | P | P (data) | P | **F5** | N/A | O7 | P | N/A |
| 12 | Mac · upcoming toggle, folded | P | P | P | P | **F5** (count) | ~ | **F3** | P | N/A |
| 13 | Mac · upcoming run rows | P | **F7** | O5 | P | **F5**, **F6** | ~ | **F7** | P | N/A |
| 14 | Mac · past run rows | P | **F7** | P | P | **F5** | P (↗ tail) | **F7**, **F8** | P | N/A |
| 15 | Mac · past toggle, folded | P | P | P | P | **F5** | ~ | **F3**, F8 | P | N/A |
| 16 | Mac · rail | P (aligned; board has a 1pt jog) | **F7** | N/A | N/A | **F6** | N/A | **F3** | P | N/A |
| 17 | Mac · model chip, Claude Code (`opus`; "Claude default") | P | P | P / O2 | P | **F9**, F5 | P | ~ (radius at 1x) | N/A | N/A |
| 18 | Mac · model chip, Codex ("Codex default") | P | P | O2 | P | **F9**, F5 | P | ~ | N/A | N/A |
| 19 | Phone · whole screen: scroll end vs ask bar and fade | — | **F4** | — | — | O3 | — | **F4** | — | P |
| 20 | Mac · whole window context | P | P | — | — | F5 (page-wide) | — | O7 | — | ~ (glass items blank: capture limit) |

## 3. Findings

**F1. Phone grey text is 21 levels darker than the board.**
- Board `#A1A1A6` (161,161,166). App about (140,140,143) at the 3x plateau.
- Affected text:
  - "Runs" heading and "23 runs · 22 completed"
  - "8 later", "21 earlier" and "11 earlier"
  - upcoming run heads
  - tails ("5 min ›")
- All of these read 139–140 in the app, against 161 on the board, with identical geometry.
- Calibration: body text reads 209 vs 209, so this is not codec drift. The 1x PNG agrees (p99 152 vs the board's 161 glyph core).
- Pairs: `crops/p01-runs-header-*`, `p02-*`, `p03-*`, `p04-*` (tails), `p05-*`.
- Cause (hypothesis): `.foregroundStyle(.secondary)` (iOS secondaryLabel ≈ 141 on black) in `TaskDetailViews.swift`.

**F2. The phone rail line is about 9 levels darker.**
- Board `#48484A` (72,72,74). App 61–65:
  - 3x frame: 61 across a full 6px line
  - 1x PNG: the line straddles 3 px (45, 67, 18), a sum of 130 over 2px, so about 65
- Pairs: `p06-rail-strip-*`.
- Cause (hypothesis): `Color.secondary.opacity(0.45)`.
- The hollow upcoming ring matches (99/100 vs `#636366`).

**F3. The dashed rail stubs beside toggles have open gaps; the board's are nearly solid.**
- **Phone board** (Chrome `2px dashed`, 13pt stub): 3 dashes of about 4pt with 0.5–0.7pt gaps. The last dash runs into the solid rail.
- **Phone app:** a [4,3] pattern, so 2 dashes with 3pt gaps, plus a 2pt gap before the solid rail (app 606.3–608.3pt in board coordinates).
- **Mac board:** about 3.3pt dashes with 2pt gaps. **Mac app:** 4pt dashes with 3pt gaps.
- Pairs: `p07-toggle-dash-zoom-*` (best view), `p02`, `p05`, `p08`, `m02`, `m04`.
- Cause (hypothesis): `StrokeStyle(lineWidth: 2, dash: [4, 3])`.
- This is minor. The board's look comes from Chrome's dash fitting, so the owner may accept a [4,1] or similar pattern as the intent.

**F4. On the phone, the last toggle never clears the bottom fade.**
- **Board:**
  - The last toggle ends at 844, which is 76pt above the ask bar's top (920).
  - The fade starts at 870, 50pt above the bar, and reaches 0.74 at the bar's top.
  - The toggle therefore sits at full contrast.
- **App at maximum scroll** (same in the folded and past-opened states):
  - The toggle spans 702–746 and the bar's top is at 782 (36pt clearance).
  - The fade starts at about 712, 70pt above the bar, and is opaque by about 784.
  - Measured on the rail at scroll 0: 62 at 712, 46 at 732, 33 at 748, 4 at 780.
- **Result at rest:**
  - "Show more" (52,126,208) vs (65,154,255) on the top toggle, about 80%
  - "21 earlier" 115 vs 140
  - the dashed stub below the disc 32–40 vs 61
- Pairs: `p05-toggle-earlier-*`, `p13-toggle-earlier-after-open-*`; full screens `app/phone-folded-bottom-1x.png` and `app/phone-past-open-b-3x.png`.
- Fix direction: more bottom content inset (about +40pt), and/or start the fade 50pt above the bar as the board does.

**F5. Mac text tokens differ from the board, in both directions.** All values are sRGB, 1x plateau (p90).
- Run heads: (224,224,224) vs `#F4F4F6` (244,244,246), 20 levels dimmer.
- Run body: (193,193,194) vs `#C9CBD3` (201,203,211), 8–17 levels dimmer and without the blue tint.
- Greys ("Runs", count, "8 later", "12/21 earlier", upcoming heads, tails): (161,162,163) vs `#8A8A93` (138,138,147), **23 levels brighter**.
- The board's hierarchy (244 → 201 → 138) is compressed to 224 → 193 → 161 in the app.
- The same shift is page-wide: title 224 vs 244, instructions 216 vs (228,229,234), "Instructions" heading 161 vs 138. Earlier rounds did not flag those.
- Pairs: `m01`–`m04`.
- Cause (hypothesis): system label colours (`.primary` / `.secondary`) instead of the board's hex values.

**F6. The Mac rail and hollow nodes are much brighter than the board.**
- Rail line: (92,94,95) vs the board's rendered (65,65,69) (`rgba(255,255,255,0.14)` on `#1B1B1E`). That is +27.
- Upcoming ring: (120–124) vs `#5A5A62` (91,90,98). That is +30.
- Ring interior: (33,33,35) vs transparent (26,26,30).
- Pairs: `m03-run-rows-*`, `m01`.
- Cause (hypothesis): `Color.secondary.opacity(0.45)` and `.opacity(0.7)` resolve brighter against macOS's secondary label.

**F7. Mac run nodes are 1pt larger, and the run text sits 2pt further right.**
- **Nodes:** 12pt vs 11pt (board `11×11`). This applies to the hollow and the green nodes.
- **Run text column:**
  - Board run heads start 26pt in from the page content edge (x 44 from 18). The app's start 28pt in (x 48 from 20).
  - Toggle labels match at 28pt in both.
  - The app aligns the rail at 8pt in for both row types. The board has its run rail at 7pt and its toggle disc at 8pt, a 1pt jog that is a board artifact.
- Pairs: `m03-run-rows-*`, `m01`.
- The app appears to reuse the phone's 12pt node and 16pt rail column on Mac.

**F8. Mac past rows are slightly shorter (minor, at the 1x limit).**
- Row pitch: about 51pt vs 52.1. Measured twice: green node tops 567→618, and head caps 565→616. The board's are 566.3→618.3 and 565.0→617.0.
- The body sits about 1.5pt closer to the head: 18 vs 19.7, cap to cap.
- Cumulative effect: the bottom toggle disc is 2.7pt higher than the board's (668 vs 670.7).
- Pair: `m03`, `m04`.

**F9. Mac chip fill is 8 levels darker.**
- App (38,38,43), the same as the card fill `#26262B`. Board: `rgba(255,255,255,0.07)` on `#1B1B1E`, rendered (46,46,50) on both the runs board and the pill board.
- This is shared by the Pro, model and folder chips.
- Geometry matches: height 24, icon at +6pt, Claude logo 13×13, Codex logo 14×14, gap 5, trailing pad 9–10 (board 8.3–8.7, 1x).
- Pairs: `m05`, `m06`, `m07`.

**F10. The phone failure red is slightly bluer (minor).**
- Node (255,66,69) vs `#FF453A` (255,69,58) in the 1x PNG, fully covered.
- Body text has the same hue shift.
- Pair: `p11-failed-row-*`. Geometry, Retry (#409CFF) and the layout match.

### Verified matches, for the record
**Phone Runs section** (the app is 12pt wider, and right-aligned items shift accordingly):
- Row heights: toggles 44, upcoming 37, past 59.
- Rail column at x 20–36. Disc 18pt (#1C1C1E), chevron about 7.3×4.7pt (#409CFF).
- Hollow node 12pt, 2pt ring (99,99,102), black interior. Green node (48,209,88).
- Text x 48.67 and every cap line within 0.33pt. Font sizes from cap heights: 15 semibold, 13 semibold tails, 15 regular body.
- Count right edge at the content edge.
- "Show less" opened state: no count, no rail above, chevron down, dashed below.
- The upcoming→past join is continuous.

**Phone chips** (both Claude and Codex):
- Height 26, fill (28,28,30).
- Icon at +7pt, Claude 14×14 at (217,116,87) vs #D97757, Codex 15×15 tile matching.
- Gap 5.67, trailing pad 9.67, text (214,214,216) vs #D1D1D6.

## 4. Observations (not counted)

- **O1. Phone chip for model id `opus` reads "Opus".** The boards show the same task as phone "Opus 5.5" and Mac "opus", which implies the phone resolves the alias to the versioned name. Per the brief, model names are data, so this is not counted. Owner question: should `opus` read "Opus 5.5" on the phone? Pair: `p16-chip-opus-*`.
- **O2. Mac chip reads "Codex default" / "Claude default"** for stand-in tasks with no model id. The board only shows the raw-id case (`opus`, `gpt-6-astra`). The raw-id case was verified on task 03: "opus" renders correctly. The Codex raw-id case was not reachable without editing a task.
- **O3. Phone content shows below the ask bar.** In the strip between the bar's bottom (834) and the screen edge, the rail dash reads 61 at y≈840, which is unfaded. The board covers this area with 0.96 black. This is part of the shared ask-bar fade, which passed earlier rounds. It is flagged because the runs rail shows through.
- **O5. Time strings use a narrow no-break space** ("9:00 AM", system formatting). The board uses a normal space. This is formatting/data and was not counted.
- **O6. Phone text runs about 2.5% narrower** ("Show more" 78.7 vs 80.7pt). This is SwiftUI's SF tracking vs Chrome, a renderer difference.
- **O7. Mac page inset is 20pt vs the board's 18pt** for the title, chips, "Runs" and the rail. This is page-wide and outside scope (earlier rounds passed it). It shifts the whole Runs section 2pt right.

## 5. Whole-screen and interaction checks

- **Upcoming toggle:** one tap shows all 10 upcoming runs. The label becomes "Show less" with no count, the chevron flips down, and the dashed stub above the disc disappears. The scroll position is unchanged (Runs header stayed at y=439). This matches the board's state logic.
- **Past toggle:** one tap adds 10 runs (12 shown) and the label reads "Show more · 11 earlier", which matches the board's `older + 10` logic. The failed run (Tue Oct 13) renders with a red node, Retry and a red reason, like the board.
- **Not exercised** (not requested): collapsing back with Show less, the past group's final "Show less" state, and the next tap ("1 earlier").
- **Phone scroll end:** see F4. Content below the bar: see O3.
- **Mac:** the window shot draws the glass toolbar items as blank capsules (a capture limit, out of scope).

## 6. Coverage gaps

- **Mac is 1x only:** chevron size (app 7×5 px vs board 5.7×3.7pt), corner radii and dash lengths are ±1pt. These are marked "~".
- **Phone app build identity:** the app is the installed build as found. The repo HEAD and dirty tree are recorded, but the exact build revision is unknown.
- **Open board's bottom toggle:** it is under the board's own ask bar, so it was judged from the DOM plus the folded board's identical template.
- **Mac Codex raw-id chip** ("gpt-6-astra") was not rendered by any stand-in task. Only the geometry and logo were compared, using "Codex default".
- **Chrome tab 1045567207** is still open. This harness has no tab-close tool, and `window.close()` was refused.

## 7. Files

All paths are under `/Users/eugenechan/dev/personal/lfg/.claude/tasks-a2/evidence/verifier-runs/`.
- **Board captures** (`design/`):
  - `phone-folded-runs-3x-y530.png`, `phone-folded-board-1x.png`
  - `phone-open-3x-y{530,850,1170,1431.33}.png`
  - `model-pill-phone-3x-y0.png`, `model-pill-mac-3x-y150.png`
  - `mac-runs-3x-y425.png`, `mac-board-1x-401w.png`
- **Phone captures** (`app/`):
  - folded: `phone-folded{,-scrolled}-3x.png` with `-1x.png` siblings, and `phone-folded-bottom-1x.png`
  - upcoming opened: `phone-later-open-{a,b}-3x.png`
  - past opened: `phone-past-open-{a,b,c}-3x.png`
  - chips: `phone-{claude,codex,opus}-top-3x.png`
  - the `.mov` recordings they came from
- **Mac captures:** `app/mac-task{45,07,03}.png` (raw) and `app/srgb/` (used for colour).
- **Paired crops:** `crops/*-design.png` / `*-app.png` (25 pairs), `crops/review-0{1..5}.png` (browse sheets) and `crops/index.json` (source and crop hashes, pixel boxes). Manifest: `crops-input/pairs.json` (generator `make_manifest.py`).

## 8. Timing and tool recovery

| Phase | Observed time (HKT) | Notes |
|---|---|---|
| Preparation | 23:19:51–23:21:30 | Board hashes and source, helper, listeners; Mac bundle built in background (23:20:16–23:20:45) |
| Board capture | 23:21–23:23, 23:30–23:31, 23:35–23:36, 23:39–23:41, 23:46 | DOM dumps + zoom-3 native captures |
| App capture | 23:20–23:38 (phone), 23:38–23:44 (Mac) | Three Runs states, three chip tasks, three Mac tasks |
| Comparison | 23:24–23:48 (interleaved) | Pixel profiles, ink boxes, colour plateaus, 25 crop pairs |
| Report | 23:48–23:55 | |

Tool failures and recoveries (each recorded once):
1. **Chrome full screenshots are downscaled JPEG.** I used the zoom action at scale 1, which gives native PNG. A 1680×900 region was still downsampled, so I split it into two 1200×450 regions.
2. **`ffmpeg -sseof` silently produced no frame** for two short recordings. I extracted the first frame instead; the screens were static.
3. **`flowdeck ui simulator scroll --direction UP` stopped moving near the top.** I used a `swipe` from 250 to 750 instead.
4. **The crop helper rejected one rect outside the viewport.** I re-chose rows that sit fully on screen.
5. **My chip-measuring script merged adjacent chips** when the search rect overlapped them. I re-measured with tight rects; only the tight-rect values are reported.
