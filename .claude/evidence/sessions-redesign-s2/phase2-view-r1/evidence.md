# Phase 2 session view (phone): verification round 1

**Verdict: PARTIAL.** The structure, copy, colors and states match on all 7 boards. Several measured layout and type deltas remain (listed below).

## Scope and method

- Design: the 7 boards (plus `s2-question-permission` and `s2-question-plan` copies), rendered from `http://127.0.0.1:8793/` in Chrome. I read every expected value from the rendered DOM (`design/*.txt` = computed rect, font, color and radius for every visible element). The 1x board shots are in `design/`.
- App: iPhone 17 Pro sim `C47EB72F…`, fixtures `working`, `queued`, `failed`, `question`, `permission`, `plan`, `signin`. Captured with `flowdeck … record` at 3x (1206×2622 = 402×874 pt), in `app/`.
- Measurements: pixel scans of the 3x frames. Font size comes from cap height ÷ 0.7046 (SF Pro). Gaps are measured glyph to glyph, and boxes by color-run scans. I did not compare text widths (SF Pro on iOS is narrower; the owner accepted this).
- Pairs: `crops/full_b*.png` puts the full board next to the app. `crops/b*_*.png` are component crops. The design side of each pair is the 1x shot upscaled, or a 1.75x render for `b1_*`.

## Per-board / per-component table

| Board | Component | Internal uniformity | Structure | Copy | Type | Color | Glyphs | Spacing/shape | State |
|---|---|---|---|---|---|---|---|---|---|
| 1 s2-view | Top bar | PASS | PASS | PASS | PASS (title 17/600, status 12) | PASS | accepted (system glass) | PASS | PASS |
| 1 | Transcript | PASS | PASS | data only | **FAIL**: body and bubble text are 16pt, design is 17px | PASS | PASS | **PARTIAL**: bubble max width, step-row rhythm, bottom clearance | PASS |
| 1 | Pills row | PASS | PASS | PASS | PASS (14/500) | PASS | PASS (ring, file, terminal) | PASS (16 inset, 8 gap, 36 high) | PASS |
| 1 | Composer | PASS | PASS | PASS | PASS (17 placeholder, 13 chip) | PASS | PARTIAL (chip chevron larger) | PASS (12 inset, 95 high, 28 bottom; chip 131×28; stop 34) | PASS |
| 2 tools-group | Group header + rail + rows | PASS | PASS | data only | PASS (15 / 14 / 12.5 mono / 12) | PARTIAL (open-header chevron #646464, design #8E8E93) | PASS | PASS (rail x24, 1.5pt; rows 29 vs 28 pitch) | PASS |
| 2 | Call card | PASS | PASS | PASS | **PARTIAL**: result line pitch 14, design 16 | PASS | — | PARTIAL (input pitch 16 vs 17; top pad 11.7 vs 13.5) | PASS |
| 3 tools-single | Single row + card | PASS | PASS | PASS | **PARTIAL**: output pitch 14 vs 16 | PASS | PASS | PARTIAL (box 127 vs 144 high; ellipsis vs clip) | PASS |
| 4 queued | Status line | PASS | PASS | PASS ("· 1 queued · Pro") | PASS | PASS | — | PASS | PASS |
| 4 | Strip row | PASS | PASS | PASS | PASS (13) | PASS | PASS | PASS (12 inset, 32 high, 6–8 above composer) | PASS |
| 4 | Row menu | — | PASS (items and order) | PASS | system | system | system | **PARTIAL**: anchor covers the row | PASS |
| 5 failed | Status / strip / placeholder | PASS | PASS | PASS | PASS | PASS (#FF6961 "Not sent") | PASS | PASS | PASS |
| 5 | Disabled send | PASS | PASS | — | — | **FAIL**: about 50% dimmer than design | PASS | PASS | PARTIAL |
| 5 | Row menu | — | PASS (Retry, Edit, Delete) | PASS | system | system | system | **PARTIAL**: same anchor delta | PASS |
| 6 question | Panel | PARTIAL (soft shadows under rows, faint badge; visible only when contrast is stretched) | PASS | accepted header | PASS (20/600, 15, 16/500, 13/700) | PASS | PASS | PARTIAL (subtitle pitch 18 vs 20) | PARTIAL (free-text send dimmed) |
| 6 permission | Panel | PASS | PASS | **PARTIAL**: footer copy | PASS | PASS | PASS | PASS (48pt buttons, 8 gap; cmd box 35.7 vs 38) | PASS |
| 6 plan | Panel | PASS | PASS | PASS | PASS (15, 14 link) | PASS | PASS | PARTIAL (item pitch 22 vs 25) | PASS |
| 7 signin | Panel | PARTIAL (same soft shadows) | PASS | PASS (step copy is fixture data) | PASS (12/20/15/16/13/17) | PASS | PASS (G badge, key) | PARTIAL (panel 315 vs 328 high) | PASS |
| whole screen | Top scroll edge | **FAIL** | — | — | — | — | — | — | — |

## Deltas (design value vs app value, both measured)

1. **Transcript body text size, all boards.** Assistant text and user-bubble text use 17px in the design. The app measures 16pt: the capital 'I'/'B' is 11.33pt high, and a 17pt cap would be 11.98. As a check in the same frame, the 17pt title 'F' measures 12.0pt, the 17pt placeholder 'A' measures 12.33pt, and the 16pt option 'Y' measures 11.33pt. The word "fork" is 28.0pt wide in body text and 28.3pt in the bubble, so the bubble is 16pt too.
2. **User bubble maximum width.** Design: `max-width:290px` content plus 14+14 padding, so the bubble is 318 wide (x 56–374). App: 289pt outer, about 261pt of content (x 96.7–385.3). Discriminating case on the sign-in fixture: line 1 is 258pt and " list" adds about 24pt, so 282pt would fit in 290 and not in 261. The app wraps before "list", which confirms the narrower maximum. Crop: `crops/b1_transcript.png`.
3. **Top scroll edge (whole screen).** Design: the transcript is clipped at y=112, and an opaque black scrim covers y 0–89 and fades out by y 124. Nothing ever sits under the title or status line. App: scrolled content shows through behind both. Over a blue bubble the pixel values are about 12% of full at y76 (title) and 25% at y94 (status line), and reach full strength at about y148. In `q2_single`, the bubble text "when i tap fork on desktop or" overlaps "Working · 4m 8s · 1 queued · Pro". Crop: `crops/scroll_edge_top.png`. Also visible in `w3_card`.
4. **Code/result line height, boards 2–3.** Design `11.5px/16px`; app pitch 14.06pt. The 6-line box is 99.3pt (design 112). The 8-line box is 126.7pt (design 144). Overflow also differs: the design clips (`white-space:pre; overflow:hidden`) and the app adds "…". The input line pitch is 16pt (design 17).
5. **Step-row vertical rhythm.** Bubble to the step-row cap top: design 15.7 (question board) and 17.7 (sign-in); app 25.1 and 25.3. Step-row baseline to the next paragraph's cap top: design 25.8 (view) and 21.8 (question); app 18.6 and 19.7. Paragraph to step row is the same: 25.6 vs 26.0. In the app the step row sits closer to the paragraph below it.
6. **Transcript bottom clearance above the pills, board 1.** From the "Edited 2 files" baseline to the pill top: design 19.7, app 32.6. The last transcript row ends about 198pt from the bottom, versus 180 in the design.
7. **Disabled send, board 5.** Design: background #3A3A3C, arrow #8E8E93. App: #2A2A2D and #58585A, which matches the design colors at about 50% opacity over the composer. The question panel's free-text send is similar: design #48484A with a white arrow, app #303033 with a #979799 arrow.
8. **Strip-row menu anchor, boards 4–5.** Design: the menu sits 8px above the row, its trailing edge aligned to the row's trailing edge (x 128/148–378), so the queued text stays visible. App: the menu is centered (x 77–325) and its bottom lines up with the row bottom (y 566–744). It covers the row. Tapping the "…" end (`q4_menu_from_ellipsis.png`) gives the same position. Items and their order match. Icon side and width are system rendering, which the owner accepted.
9. **Permission footer copy.** Design: "Always allow fastlane in this folder" on one line. App: "Don't ask again for fastlane commands in this folder" on two lines. `NeedsInputPanelModel` derives this label from the CLI option text, so it may be intentional. It needs an owner decision.
10. **Minor:**
    - The expanded group-header chevron is #646464; design #8E8E93.
    - The model-chip chevron is 8.3×6.3pt; design is about 5.6×3.9 (9px svg).
    - Panels are 10–13pt shorter. The subtitle pitch is 18 vs 20 and the plan item pitch is 22 vs 25 (the 4px gap is missing).
    - The call card's top padding is 11.7 vs 13.5.
    - The option-row badge shows faintly (#2E2E30 on a #272729 row); in the design it is the same color as the row.
    - The option rows, card and button carry soft drop shadows. These show only when contrast is stretched (`crops/n1_panel_levels.png`, `s1_panel_levels.png`).

## Confirmed correct

- Status lines for all five states: dot with ring, semibold colored lead, grey tail. Title is 17pt, status 12pt, and the green, orange and grey values match.
- Pills row: 16pt inset, 8pt gaps, 36pt height, #38383A hairline. The ring arcs are #30D158/#FF453A, the labels 14pt with #8E8E93 counts, and the Terminal pill sits at the end of the row and scrolls.
- Composer: 12pt insets, 95pt height, 28pt from the bottom. Placeholder is 17pt #8E8E93. Chip is 131×28 at 13pt #D1D1D6. Stop is a 34pt #F2F2F7 circle with an 11pt square, 10pt inset.
- Tool group: magnifier, 15pt label, "N steps · Ns" meta. Rail at x24, 1.5pt #363636. Row icons, 14pt verb #D1D1D6, mono 12.5 target #A1A1A6, 12pt duration #8E8E93, chevrons #636366.
- Call cards: #1C1C1E-class fill with hairline, 11pt uppercase labels, black result box, #409CFF "Show all" link, green "42 pass".
- Queued strip: 32pt high, spinner, 13pt text with ellipsis, "…" icon, sits above the composer. Failed strip: red "!" icon and "Not sent" #FF6961. Offline placeholder "Message · sends when Air is back".
- Needs-input panel for all three kinds: 8pt insets, the header label and Dismiss chip, 20pt title, 48pt option rows 8pt apart, 44pt free-text field. The permission and plan button grids are 48pt high with an 8pt gap. Pills and composer are hidden while the panel is up.
- Sign-in panel: header, title, subtitle, site card with the G badge, 50pt blue button with the key glyph, and the footnote.

## Excluded / accepted / not verified

- Accepted by the owner, so not counted: the system glass back and tools buttons, the system menu material and icon side, sample text, the header without "· 1 of 1", "Medium", pills omitted on boards 4–7, the clipped last pill, and text width.
- Design inconsistencies, not counted: the body color is #F2F2F7 on s2-view and #FFFFFF on s2-question, and the app uses #FFFFFF. The chip on board 5 has no chevron, but it has one on board 1. Board 4 draws the collapsed single call as plain text, and board 3 uses the mono/duration form, which the app follows.
- Transient state: right after opening the offline `failed` session, the app shows "Loading earlier messages…" with a spinner for at least 8s (`f1_view.png`). It was gone about 60s later. The board does not show it, and I did not time how long it lasts.
- Not verified: the bottom fade under the pills when content is scrolled behind them. The transcript in these fixtures never reached the pills.
