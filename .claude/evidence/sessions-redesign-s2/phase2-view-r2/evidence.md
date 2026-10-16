# Phase 2 session view (phone), round 2: design verification

**Verdict: PARTIAL.** All 7 boards (9 renders, counting the permission and plan kinds) match on structure, copy, colors, glyphs and states. Most round-1 deltas are fixed. Two layout deltas remain on several boards, plus a few small metric gaps.

1. Tool-step rows and needs-input panels sit 5 to 7 pt lower after a prose block than the boards place them.
2. Scrolled content still shows faintly under the status line, where the board shows black.

## Scope and method

- Design: the local render at `http://127.0.0.1:8793/` in a new Chrome tab. Each board was captured at 390×844 1x (`design/`). Every expected value comes from the board's computed DOM (`getBoundingClientRect` and `getComputedStyle`) and its source.
- App: iPhone 17 Pro sim `C47EB72F-A352-44C9-8A80-9F13D33780AD`, using the `LFG_S2_VIEW_FIXTURE` modes `working`, `queued`, `failed`, `question`, `permission`, `plan` and `signin`. Frames were taken with `flowdeck … record` and the last frame kept. They are 3x (1206×2622 = 402×874 pt), in `app/`.
- Measurement: a pixel probe (row and column runs, color sampling) on the 3x frames. Distances are glyph-edge to glyph-edge, compared with the same measure on the board capture (±1 pt at 1x).
- Color tolerance: frames are h264. Flat fills read within 4 levels (bubble #066CDE vs #0A6EE0), and small text reads 6 to 9 levels brighter. A color counts as a delta only when it is more than 15 levels off.
- Paired crops (design upscaled 3x | app 3x) are in `crops/pair-*.png`.

| App frame | State |
|---|---|
| w0 | working, collapsed |
| w1 | group expanded |
| w2, w3 | call card open (w3 scrolled so the open row shows) |
| w4 | pills scrolled to Terminal |
| w5 | model-chip menu |
| q0 | queued |
| q1 | single call opened |
| q2 | menu with the card open |
| q3 | menu, step collapsed |
| q4 | "Edited 2 files" expanded |
| f0, f1 | failed, then its menu |
| k-question, k-permission, k-plan | the three panel kinds |
| s0 | sign-in |

## Per-component table

| Board | Component | Consistency | Structure | Copy | Type | Color | Glyphs | Spacing / shape | State |
|---|---|---|---|---|---|---|---|---|---|
| 1 view | Top bar / status | PASS | PASS | PASS | PASS (17/600; 12) | PASS | PASS (7pt dot + 3pt ring) | PASS | PASS |
| 1 | Transcript | PASS | PASS | data only | PASS (17pt prose, 24pt pitch; bubble 17) | PASS | PASS | **PARTIAL (D1)** | PASS |
| 1 | Pills | PASS | PASS (Subagents, Files, Terminal on scroll) | PASS | PASS (14/500) | PASS | PASS (ring arcs) | PASS (x16, 36h, 8 gap) | PASS |
| 1 | Composer | PASS (uniform #1A1A1C) | PASS | PASS | PASS | PASS | PASS (chevron 5.7×3.7 vs 6×3) | PASS (12 insets, 95h, r24, 28 bottom) | PASS (Stop) |
| 2 tools-group | Header + rail + rows | PASS (rail continuous) | PASS | data only | PASS | PASS (open chevron #919191 ≈ #8E8E93) | PASS | PASS (row pitch 29 vs 28) | PASS |
| 2 | Call card | PASS | PASS | PASS | PASS (result pitch 16; input pitch 18 vs 17) | PASS | — | PASS (237h = 237; 13pt insets; r12) | PASS |
| 2 | Prose → group header | — | — | — | — | — | — | **PARTIAL (D1)** | — |
| 3 tools-single | Row + card | PASS | PASS | PASS | PASS (mono 13) | PASS | PASS | PASS (272.3h vs 272; box 144 = 144) | PASS |
| 4 queued | Status / strip | PASS | PASS | PASS ("1 queued · Pro") | PASS | PASS (bg #18181A closed, #2E2E31 open ≈ 0.22 / 0.40) | PASS | PASS (32h, r16, 6 above composer) | PASS |
| 4 | Row menu | PASS | PASS | PASS | PASS (17 + 13) | PASS (#29292C, separators #464649, Remove #FF453A) | PASS | PASS (250w, right 12, 8 above row, 141.5h vs 141) | PASS |
| 5 failed | Status / strip / composer | PASS | PASS | PASS | PASS | PASS (dot without ring; "Not sent" ≈ #FF6961; send #38383B + #949497) | minor (send arrow 12.7×15 vs ~11×11) | PASS | PASS (no Terminal pill when offline) |
| 5 | Row menu | PASS | PASS (Retry, Edit, Delete) | PASS | PASS | PASS | PASS | PASS (230w, 128h, 8 above row) | PASS |
| 6 question | Panel | PASS (badge invisible, no shadows) | PASS | accepted header | PASS (20/600, 15, 16/500, 13/700) | PASS | PASS | **PARTIAL (D3)**: title→body 8.3 vs 12; input 44 vs 46 | PASS (composer and pills hidden) |
| 6 permission | Panel | PASS | PASS | PASS ("Always allow fastlane in this folder") | PASS | PASS | PASS | minor: command box 35.7 vs 38 | PASS |
| 6 plan | Panel | PASS | PASS | PASS | PASS (item pitch 25 = 25) | PASS | PASS | PASS | PASS |
| 6 | Prose → panel | — | — | — | — | — | — | **PARTIAL (D1)**: 23.3 vs 17 | — |
| 7 sign-in | Panel | PASS | PASS (no Dismiss) | data only (step line) | **PARTIAL (D4)**: footnote leading 15.7 vs 18 | PASS | PASS (G badge, key) | PARTIAL: panel 319.7 vs 328; card 57.3 vs 59 | PASS |
| whole screen | Top scroll edge | **PARTIAL (D2)** | | | | | | | |
| whole screen | Bottom edge (above pills, between pills and composer) | PASS: text is cut at the pill top; a ≤20% ghost shows in the 10pt gap | | | | | | | |

## Deltas (both sides measured)

**D1. Spacing above tool-step rows and panels after prose (boards 1, 2, 6).** Each figure is the distance from the prose baseline to the cap top of the next row.

| Transition | Board | App | Difference |
|---|---|---|---|
| Prose → step, board 1 | 25 | 30.3 | +5.3 |
| Last prose line → "Edited 2 files", board 1 | 24 | 30 | +6 |
| Prose → group header, board 2 | 23 | 30.3 | +7.3 |
| Prose → question panel, board 6 (glyph bottom to panel top) | 17 | 23.3 | +6.3 |
| Bubble → step, board 6 | 15 | 19.3 | +4.3 |
| Step → next prose line | 25 | 23.3 | −1.7 |
| Bubble → prose, board 1 (glyph gap) | 19 | 17.3 | −1.7 |

The step row is about 3.6 pt below the midpoint between its neighbours, and each prose-plus-step block is about 3 pt taller. Crop: `crops/pair-b1-transcript.png`.

**D2. Top scroll edge.**

- Design: the transcript viewport starts at y112, so nothing renders above it. The scrim is solid to y89 and clear by y124.
- App: the fade profile is close. Measured over a blue bubble at x75: black to y94, 14% at y100, 44% at y110, full at about y130.
- The difference: content renders up to about y95 instead of being clipped at 112. A ghost of up to about 18% sits under the status-line glyphs (y89–102), and 18–55% shows in the y102–114 band, where the board is black. In `q1`, the bubble edge sits behind "· 1 queued · Pro" with faint letters to its right.
- This is much better than round 1, where the title was already at 12%. Crop: `crops/pair-top-edge-b3-vs-q1.png`.

**D3. Question panel, title to body.** The glyph gap is 12 on the board and 8.3 in the app. The free-text field is 44 high (board 46).

**D4. Sign-in footnote leading.** The two 13pt lines have an 18 pitch on the board and 15.7 in the app. With the card at 57.3 vs 59 and the body offset −1.7, the panel is 319.7 tall vs 328.

**Minor (each under 3 pt):**

- Call-card input line pitch: 18 vs 17.
- Group call-row pitch: 29 vs 28.
- Card left edge: 37.7 vs 39, against the call-icon column.
- Permission command box: 35.7 vs 38 high.
- Disabled-send and panel-send arrows are a taller SF glyph: 12.7×15 vs about 11×11.

## Observations outside the board diffs

- **Files pill rule.** The `queued` fixture's transcript names files (`q4`: "Edited ios/LFG/SessionStore.swift" and "Edited desktop/LFGSessions.swift"). Only a Terminal pill shows, while `working` shows "Files 4" for the same transcript. The accepted rule says Files shows "when the transcript names files". It may be fixture data (a server-side files list). The owner should check.
- **Panel kinds and sign-in board.** The permission and plan renders leave a large gap between the transcript and the panel. The sign-in board leaves a 36px gap. The cause is a fixed `transcriptBottom` (420px and 372px in the source), not intent, so the app anchoring the transcript to the panel top is not a delta.
- **Model-chip menu.** No board in scope shows it (`crops/w5-chip-menu.png`). It lists GPT-5.6 Sol, GPT-6 Luna, GPT-6 Sol, GPT-6 Astra, GPT-6.1 Sol, then "Switch in place": Haiku 5.5, Sonnet 5.5, Fable 5.1, Opus 5.5, then "Change the model when this turn ends". In the captured portion, the current model shows no checkmark and there are no effort items; the menu may scroll. Not graded.

## Round-1 deltas re-checked: fixed

| Round-1 delta | Now |
|---|---|
| Prose and bubble 16pt | 17pt: cap 'I' 12.0, line pitch 24 |
| Bubble max width | 318 = 318 |
| Result line pitch 14 | 16; boxes 112 and 144 |
| Bottom clearance above pills | 20.3 vs 18 |
| Disabled send at 50% | #38383B / #949497 |
| Menu anchor covering the row | 8 above the row, trailing edge aligned, 250 and 230 wide |
| Footer copy | "Always allow fastlane in this folder" |
| Subtitle pitch | 20 |
| Plan item pitch | 25 |
| Open-header chevron | #919191 |
| Chip chevron size | 5.7×3.7 |
| Option badge and soft shadows | Badge invisible, no shadows |

## Confirmed correct

- Status lines in all five states: green with ring (working), orange without ring (offline, needs input, needs sign-in), grey tail, matching copy.
- Pills: 16pt inset, 36h, 8 gaps, hairline, ring arcs green/red/track, 14/500 labels with #8E8E93 counts. Terminal is reachable by scrolling and hidden when offline.
- Composer: 12pt insets, 95h, r24, 28 from bottom, 17pt #8E8E93 placeholder, paperclip, 28h r14 chip at 13/500, 34pt Stop with 11pt square.
- Group: magnifier, 15pt label, "N steps · Ns" at 12pt #8E8E93. Rail at x24 in #363636. Row columns x39.7 / 61 / 93.7, durations and chevrons at 19pt inset.
- Call cards: 13pt insets, 11pt uppercase labels, mono input, black result box with 16 pitch, #409CFF link, green pass line.
- Queued strip and menu, failed strip and menu (Retry / Edit / Delete), and the strip highlight while a menu is open.
- Question, permission and plan panels: 8pt insets, r32, 8 bottom, header dot with ring, #FFB340 caps label, Dismiss pill, option rows 48h with 8 gap, 48h r24 buttons, link colors.
- Sign-in panel structure: no Dismiss, G badge 32 r8, 50h r25 button with key, centered footnote.

## Not verified

- Live scroll behaviour beyond the fixtures' own content. Fades were judged on the expanded-card frames (`w3`, `q1`), which push content under both bars.
- Color values only within h264 tolerance.
- The model-chip menu: no in-scope board.
- Liquid Glass buttons, accepted as system.
