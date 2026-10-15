# Verifier round 2: "Change task" chat sheet vs `tA2d-chat` — PARTIAL

Date: 2026-10-15. Verifier: claude-design-verifier (independent). Round 1 report: `evidence.md` (FAIL, deltas D1–D14).

## Scope and method

- **Design truth:** the same 3x render as round 1 (`design-full-3x.png`), plus the DOM values from `tA2d-chat.dc.html`.
- **App:**
  - Rebuilt app on `D379DCF1-…` (iPhone 17 Pro, dark).
  - Stand-in host restarted, so the task started at "Every weekday at 9:00 AM" with no chat.
  - Message sent: the board's text.
  - Captures: 1x FlowDeck PNGs for colour, 3x frames from `flowdeck ui simulator record` for geometry.
  - Positions are measured from the top of the sheet: design 96, app 62.
- **States checked:** empty, typed, pending, working, result, close, and reopen from the Ask bar.
- **Excluded:**
  - The mic glyph. The Decision Log (line 291, "No mic button in the chat composer") records it as a deliberate difference.
  - Data differences: time of day, "Claude default" as the old model, the reply wrapping to 2 lines on the wider 402pt screen, and autocapitalisation.

## Per-component table

| Component / state | Criterion | R2 | Measured (design vs app) |
|---|---|---|---|
| Sheet surface | Internal consistency | PASS | 100% (28,28,30) in the empty sheet and below the card; no seams, no bands |
| Sheet surface | Token (was D1) | PASS | #1C1C1E vs (28,28,30) |
| Grabber | Size / position | PASS (native colour) | 36x5 in both; (97,97,104) system indicator |
| Icon tile | Size / fill | PASS | 34x34, #2C2C2E vs (44,44,46) |
| Header icon (was D2) | Glyph | PARTIAL | Now a single 4-point star, 11.4x11.3 vs 11.4x11, colour (64,157,255) vs #409CFF. It is **filled**; the board draws a 1.8pt **outline** (centre pixel: tile grey on the board, blue in the app). It is also about 2pt lower in the tile (centred; the board's path sits high) |
| Title / subtitle | Copy, type, colour, position | PASS | Cap top +25.7 vs +26. Subtitle updates to "· Tue–Fri at 8:00 AM" after the save |
| Close (was D3) | Glyph / fill / position | PASS | X 9.7 vs 9.4pt; ink (222,222,224) vs #D1D1D6 (+13, minor); circle 44 at #2C2C2E |
| Note line | Copy / type / colour | PASS | 12pt (161,161,164); text at +80.7 vs +82.7 |
| User bubble (was D4–D6) | Fill / radius / height / padding / wrap | PASS | Fill (10,110,224) vs #0A6EE0. Radius 20, same corner profile within 0.6pt. Height 66.3 vs 66. Side padding 15.3 vs 15; top/bottom ink gaps 15.3/15.7 vs 15/15.3. Line pitch 22.7 vs 23. Wraps after "instead." like the board. Right inset 16 |
| Agent reply | Copy / type / pitch | PASS | Pitch 24 vs 24 (round 1: 23) |
| **Thread spacing (D7)** | Gaps between items | **FAIL** | Note→bubble 24, bubble→reply 25, reply→card 24 (accessibility frames). The board has 14 for all three (`gap: 14px`). Ink gaps: 25.4 vs 15, 27.7 vs 19.7, 27.6 vs 20. Reply→card was close in round 1 (15) and is now too |
| Change card | Container | PASS | Fill (44,44,46) vs #2C2C2E, +16 over the sheet as on the board. Radius 20. Width 370 vs 358 (wider screen) |
| Change card | Header row (was D8) | PASS | Check 10x9.3 vs 11.4x8.4, green (48,215,89) vs #30D158. Title copy is exact. Time (159,159,161) vs #A1A1A6 |
| Change card | Labels / old / new | PASS | Labels (161,161,164). Old values about (157,157,159), struck through. New values white semibold. Row offsets match within 1.7pt |
| Change card | Schedule row layout | PASS (width-driven) | The app keeps old → new on one line (new value ends at x=370; content edge 372). The board wraps because its content is 330 wide; the same values would wrap in the app at 390pt (needs 340). Same flow rule |
| Change card | Arrow | PARTIAL | Width 8.7 vs 8.7, gaps 9.0/9.6 vs 9.6/10.4. The arrow sits about 3pt **lower**: its bottom is on the text baseline, while the board centres it at x-height (bottom 2.3pt above the baseline) |
| Change card | Model copy (was D9) | PASS | "GPT-6 Astra" |
| Change card | Divider | PASS | Hairline (66,66,68) vs #48484A at the same place in the row sequence |
| Change card | Next run (was D10) | PASS | "Next run: Fri, Oct 16 at 8:00 AM" is exact. Text (217,217,219) vs #D1D1D6. Minor: the clock is 13pt vs 10.7, the space before "AM" is a narrow space (3pt vs 5pt gap), and bottom padding is 15 vs 12.7 |
| Composer (was D12, D13) | Fill / size / placeholder | PASS | Capsule (44,44,46) on (28,28,30), +16 as on the board. 12–390 x 52 tall. Placeholder (142,142,147) vs #8E8E93. Sits 42pt above the bottom vs 30 (safe area, native) |
| **Composer Send, empty (D14)** | Resting style | **FAIL** | Circle (49–51) vs #3A3A3C (58). Arrow grey (153–160) vs white. Still drawn as disabled; the board's empty composer shows a white arrow |
| Mic | — | Excluded | By decision |
| Empty state | Structure | PASS | Header, note and composer only |
| Typed state | Behaviour | PASS | Field grows to 2 lines; Send is accent blue |
| Pending / working | Behaviour | PASS (no design) | The bubble appears at 70% opacity, (13,83,166), then goes to full. 7pt dots at x=16, 22pt under the bubble. Composer clears; Send greys out while the agent works |
| Result | Order | PASS | Note, bubble, reply, card, composer |
| Close | Task view | PASS | "Every Tuesday, Wednesday, Thursday, and Friday at 8:00 AM"; next run 8:00 AM |
| **Reopen from the Ask bar** | Persistence | PASS | Within 1 s it shows the full thread *and* the card ("Saved · 3 changes", the original 6:35 PM time, all 3 rows, next run). The sheet area (y 62–770) is **pixel-identical** to the result state (`ImageChops.difference` bbox = None). One card, no duplicate. Composer empty, not focused |
| Accessibility (was a carry-over) | IDs and labels | PASS | `task_chat_field`, `task_chat_send` and `task_chat_close` are reachable by ID (tapped by ID this round). Messages read "You: …" and "Agent: …" |

## Open deltas

1. **D7, thread spacing (main blocker).** Every gap between note, bubble, reply and card is 24–25pt in the app vs 14pt on the board, about 10pt too much each. The thread reads looser than the board.
2. **D14, Send button in an empty composer.** It is greyed: circle (49–51) and arrow (153–160). The board shows #3A3A3C with a white arrow.
3. **D2b, header star.** The app star is filled; the board's is a 1.8pt outline. Size and colour now match.
4. **D15 (new, minor), card arrow.** It sits about 3pt low, on the baseline instead of centred on the x-height.

Minor, not blocking:
- Close X ink is +13 brighter.
- The clock glyph is 13 vs 10.7pt.
- There is a narrow space before AM/PM.
- Card bottom padding is 15 vs 12.7.

## Fixed since round 1

D1, D3, D4, D5, D6, D8, D9, D10, D12, D13; bubble width and wrapping; reply line pitch; accessibility IDs and message labels; the card now survives close and reopen.

## Carry-overs

- **Scrolling:** not verified. One exchange does not overflow the thread, so the board's scroll fade under the composer was not tested.
- **Keyboard up:** not verified. The simulator is headless.
- **Out of scope:** the task view's model chip still reads "gpt-6-astra" after close.
- **Host state now:** "Daily repo review" is Tue–Fri 8:00 AM, Codex, gpt-6-astra, with one chat exchange. Sheet closed.

## Files (this folder)

- `r2-app-02-empty-{1x,3x}.png`, `r2-app-03-typed-{1x,3x}.png`, `r2-app-04a-pending-3x.png`, `r2-app-04-working-{1x,3x}.png`, `r2-app-05-result-{1x,3x}.png`
- `r2-app-06-after-close-1x.png`, `r2-app-07-reopen-t1s-1x.png`, `r2-app-07-reopen-t4s-1x.png`, `r2-app-send-recording.mov`
- Pairs (design left, app right, 3x): `r2-pair-01-header.png`, `r2-pair-01b-header-empty.png`, `r2-pair-02-note.png`, `r2-pair-03-user-bubble.png`, `r2-pair-04-agent-reply.png`, `r2-pair-05-change-card.png`, `r2-pair-06-composer-result.png`, `r2-pair-06b-composer-empty.png`, `r2-pair-07-working-state.png`, `r2-pair-08-thread-spacing.png`
- `r2-full-side-by-side.png` (design | empty | working | result)
