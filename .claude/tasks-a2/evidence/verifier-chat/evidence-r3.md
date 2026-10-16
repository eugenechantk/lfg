# Verifier round 3: "Change task" chat sheet vs `tA2d-chat` — FAIL

Date: 2026-10-15. Verifier: claude-design-verifier (independent). Earlier rounds: `evidence.md` (R1 FAIL), `evidence-r2.md` (R2 PARTIAL).

## Scope and method

Same as round 2:
- Rebuilt app on `D379DCF1-…`. The stand-in host was restarted: "Every weekday at 9:00 AM", no chat.
- Message sent: the board's text.
- Captures: 1x PNGs for colour, 3x `record` frames for geometry. Positions are measured from the top of the sheet (design 96, app 62).

States checked: empty, typed, pending, working, result, close, reopen.

Excluded: the mic (by decision), times, the "Claude default" old model, autocapitalisation, and line wraps that come from the 402pt screen.

## Per-component table

| Component / state | Criterion | R3 | Measured (design vs app) |
|---|---|---|---|
| Sheet surface | Consistency / token | PASS | (28,28,30) everywhere vs #1C1C1E; no seams |
| Grabber | Size | PASS (native colour) | 36x5 |
| Icon tile | Size / fill | PASS | 34x34, (44,44,46) |
| **Header icon** | Glyph | **FAIL (regressed)** | Now an outline (centre hollow, good), but the shape is a **diamond**. The board's 4-point star has concave sides: the side midpoint sits at 0.49 of the tip radius. The app's is at 0.73, beyond a straight-sided diamond's 0.71. Glyph 13x12.7 vs 11.4x11. See `r3-pair-09-icon-zoom.png`. Cause: `TaskStarShape` puts its curve controls at ±0.22 of the size, so the sides barely bow |
| Title / subtitle | Copy, type, position | PASS | Subtitle updates to "· Tue–Fri at 8:00 AM" |
| Close | Glyph / fill / position | PASS | X 9.7pt, ink (224,224,226) vs #D1D1D6 (minor); circle 44, #2C2C2E |
| Note line | Copy / type | PASS | Text at +80.7 vs +82.7 |
| User bubble | Fill / radius / size / text | PASS | Fill (10,110,224) vs #0A6EE0. Radius 20. 299x66.3 vs 318x66. Text 22.7pt pitch |
| Thread spacing (was D7) | Gaps | PASS | Note→bubble ink gap 15.4 vs 15. Bubble→first item 14 (frame) vs 14. Card→reply 18 vs the board's reply→card 20 |
| **Thread order** | Bubble → reply → card | **FAIL (new)** | The app shows bubble → **card** → reply (card frame y 249–474, reply y 488–532). The board puts the card *after* the reply. Reopening keeps the wrong order. Cause: the card is anchored to the message count when the save is detected (`afterMessages`). The save lands before the reply (the host saves, then replies; a real agent also calls the save tool before its final text), so the card is placed before the reply. R2 showed the right order, so the order depends on poll timing |
| Agent reply | Copy / type / pitch | PASS | 17pt white, 24pt pitch, x=17 |
| Change card | Container | PASS | (44,44,46), +16 over the sheet. Radius 20. 370 wide. 224 tall (the schedule row fits on one line at this width; the board wraps it at 330 wide) |
| Change card | Header / check | PASS | Check 10.4x9.7 vs 11.4x8.4, green. Copy exact |
| Change card | Rows | PASS | Label / old / new rows match the board within 1.7pt (first three rows) |
| Change card | Arrow (was D15) | PASS | Arrow centre 318.5 vs cap-height middle 318.35 (board: centred on x-height). Width 8.7 vs 8.7 |
| Change card | Model copy / next run / divider | PASS | "GPT-6 Astra"; "Next run: Fri, Oct 16 at 8:00 AM"; hairline divider |
| Composer | Fill / size / placeholder | PASS | (44,44,46) capsule, 12–390 x 52 tall, placeholder (142,142,147) |
| Composer Send, empty (was D14) | Style | PASS | Circle (57,57,59) vs #3A3A3C; arrow (255,255,255), white |
| Mic | — | Excluded | By decision |
| Empty / typed | Structure / behaviour | PASS | Typed: 2-line field, accent Send |
| Pending / working | Behaviour (no design) | PASS | Bubble (13,83,166) while pending, then (10,110,224). Dots at x=16, 20pt under the bubble |
| Close | Task view | PASS | "Every Tuesday, Wednesday, Thursday, and Friday at 8:00 AM", next 8:00 AM |
| Reopen | Persistence | PASS (shows the same wrong order) | Within 1 s the same thread and card ("6:43 PM", 3 rows). The sheet area is pixel-identical to the result (diff bbox = None). One card, empty composer |

## Open deltas

1. **Card above the reply (new, blocks a match).** The board order is bubble → reply → card. The app shows bubble → card → reply, and keeps that order on reopen. The order depends on timing, and in normal use the save comes before the reply text, so expect this order most of the time.
2. **Header icon is a diamond (regressed from R2).** The outline is right, but the sides need to curve inward to make the 4-point star. The glyph is also 1.6pt larger than the board's.

## Fixed since round 2

- D7, thread spacing.
- D14, empty Send style.
- D15, card arrow height.
- The header star is now an outline instead of filled; its shape is still wrong.

## Carry-overs

- Scrolling and the fade under the composer: not verified. The thread ends at y=532, so nothing scrolls.
- Keyboard up: not verified. The simulator is headless.
- Host state now: "Daily repo review" is Tue–Fri 8:00 AM, Codex, gpt-6-astra, with one exchange. Sheet closed.

## Files (this folder)

- App captures: `r3-app-02-empty-{1x,3x}.png`, `r3-app-03-typed-{1x,3x}.png`, `r3-app-04a-pending-3x.png`, `r3-app-04-working-{1x,3x}.png`, `r3-app-05-result-{1x,3x}.png`, `r3-app-06-after-close-1x.png`, `r3-app-07-reopen-t1s-1x.png`, `r3-app-07-reopen-t4s-1x.png`, `r3-app-send-recording.mov`
- Pairs: `r3-pair-01-header.png`, `r3-pair-01b-header-empty.png`, `r3-pair-02-note.png`, `r3-pair-03-user-bubble.png`, `r3-pair-04-agent-reply.png`, `r3-pair-05-change-card.png`, `r3-pair-06-composer-result.png`, `r3-pair-06b-composer-empty.png`, `r3-pair-07-working-state.png`, `r3-pair-08-thread-order.png`, `r3-pair-09-icon-zoom.png`
- Whole screen: `r3-full-side-by-side.png`
