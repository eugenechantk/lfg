# Verifier round 4: "Change task" chat sheet vs `tA2d-chat` — PASS

Date: 2026-10-15. Verifier: claude-design-verifier (independent). Earlier rounds: `evidence.md` (R1 FAIL), `evidence-r2.md` (R2 PARTIAL), `evidence-r3.md` (R3 FAIL).

## Scope and method

Same as rounds 2–3:
- Rebuilt app on `D379DCF1-…`. Stand-in host restarted: "Every weekday at 9:00 AM", "Claude default", no chat.
- Message sent: the board's text.
- Captures: 1x PNGs for colour, 3x `record` frames for geometry. Positions are measured from the top of the sheet (design 96, app 62).
- **Settling:** a 16 s recording covered the send. I also read the accessibility tree every 1.5 s for 10 s after the reply landed.

Excluded: the mic (by decision), times, the "Claude default" old model, autocapitalisation, and line wraps that come from the 402pt screen.

## Settling and final order

Times are measured from the start of the 16 s recording.

| t (s) | What is on screen |
|---|---|
| 5.56 | The bubble appears (pending) with the typing dots under it |
| 7.79 | The reply text lands under the bubble |
| 7.80 | The card appears, **below the reply** (card top 307.3), one frame after the reply |
| 8.18 | The last visual change. The screen then stays static until the recording ends at 16 s |

Accessibility frames, read 6 times from 18:50:07 to 18:50:17:
- bubble y 168–234
- reply y 249–293
- card y 307–531

These never changed. Across every frame, the card was never drawn above the reply.

**Final order: note → bubble → reply → card → composer, the same order as the board.**

## Per-component table

| Component / state | Criterion | R4 | Measured (design vs app) |
|---|---|---|---|
| Sheet surface | Consistency / token | PASS | (28,28,30) vs #1C1C1E; no seams or bands |
| Grabber | Size | PASS (native colour) | 36x5 |
| Icon tile | Size / fill | PASS | 34x34, (44,44,46) |
| Header icon (was R3 open 2) | Glyph | PASS | 4-point star outline with a hollow centre. Side-midpoint/tip ratio 0.50 vs the board's 0.49 (a straight diamond would be 0.71). Raised in the tile like the board's. Tip radius 6.15 vs 5.7pt (glyph about 0.9pt larger, minor). `r4-pair-09-icon-zoom.png` |
| Title / subtitle | Copy / type / position | PASS | Subtitle updates to "· Tue–Fri at 8:00 AM" |
| Close | Glyph / fill / position | PASS | X 9.7pt, (224,224,226) vs #D1D1D6 (minor), circle 44 at #2C2C2E |
| Note line | Copy / type | PASS | Ink at +80.7 vs +82.7 |
| User bubble | Fill / radius / size | PASS | (10,110,224) vs #0A6EE0, radius 20, height 66.3 vs 66, pitch 22.7 vs 23 |
| Thread order (was R3 open 1) | Bubble → reply → card | PASS | See above; it holds after settling and after reopen |
| Thread spacing | Gaps | PASS | Ink gaps: note→bubble 15.4 vs 15, bubble→reply 17.7 vs 19.7, reply→card 17.6 vs 20. Frame gaps 14 vs 14. The remaining ≤2.4pt is half-leading: CSS line-height splits the extra space above and below each line; SwiftUI line spacing does not |
| Agent reply | Copy / type | PASS | 17pt white, 24pt pitch, x=17 |
| Change card | Container | PASS | (44,44,46), +16 over the sheet, radius 20, 370 wide |
| Change card | Header / rows / arrow | PASS | Check 10.4x9.3, green. Row offsets match R3. The arrow sits at text centre |
| Change card | Copy | PASS | "Saved · 3 changes", "GPT-6 Astra", "Next run: Fri, Oct 16 at 8:00 AM" |
| Change card | Schedule row | PASS (width-driven) | One line at 402pt; wraps at the board's 330pt content width |
| Composer | Fill / size / placeholder | PASS | (44,44,46), 52 tall, placeholder (142,142,147) |
| Composer Send, empty | Style | PASS | (57,57,59) circle with a white arrow |
| Mic | — | Excluded | By decision |
| Empty / typed | Structure / behaviour | PASS | Typed: 2-line field, accent Send |
| Pending / working | Behaviour (no design) | PASS | Dimmed bubble while pending, then full. Dots at x=16 under the bubble. No layout jump when the reply and card arrive together |
| Close | Task view | PASS | "Every Tuesday, Wednesday, Thursday, and Friday at 8:00 AM", "Tomorrow, 8:00 AM" |
| Reopen | Persistence and order | PASS | Same order 1 s and 5 s after reopening. The sheet area is pixel-identical to the settled result both times (diff bbox = None). One card, original 6:50 PM time |

## Open deltas

None blocking. Minor, recorded only:
- The star glyph is about 0.9pt larger than the board's.
- The close X ink is +15 brighter.
- The ink gaps around the reply are about 2pt tighter (half-leading).
- The time uses a narrow space before AM/PM.

## Carry-overs

- **Scrolling and the fade under the composer:** not verified. The thread ends at y=531, so nothing scrolls.
- **Keyboard up:** not verified. The simulator is headless.
- **Out of the sheet's scope:** the task view's model chip still reads "gpt-6-astra".
- **Host state now:** "Daily repo review" is Tue–Fri 8:00 AM, Codex, gpt-6-astra, with one exchange. Sheet closed.

## Files (this folder)

- Empty and typed: `r4-app-02-empty-{1x,3x}.png`, `r4-app-03-typed-1x.png`
- Pending, working and result: `r4-app-04a-pending-3x.png`, `r4-app-04-working-3x.png`, `r4-app-05a-reply-landed-3x.png`, `r4-app-05-result-{1x,3x}.png`
- Close and reopen: `r4-app-06-after-close-1x.png`, `r4-app-07-reopen-t1s-1x.png`, `r4-app-07-reopen-t5s-1x.png`
- Recording: `r4-app-send-recording.mov`
- Pairs: `r4-pair-01-header.png`, `r4-pair-01b-header-empty.png`, `r4-pair-02-note.png`, `r4-pair-03-user-bubble.png`, `r4-pair-04-agent-reply.png`, `r4-pair-05-change-card.png`, `r4-pair-06-composer-result.png`, `r4-pair-06b-composer-empty.png`, `r4-pair-07-working-state.png`, `r4-pair-08-thread-order.png`, `r4-pair-09-icon-zoom.png`
- Whole screen: `r4-full-side-by-side.png`
