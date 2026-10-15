# Verifier: "Change task" chat sheet vs `tA2d-chat` — FAIL

Date: 2026-10-15. Verifier: claude-design-verifier (independent).

## Scope

- **Design truth:** `http://127.0.0.1:8931/tA2d-chat.dc.html`, rendered in Chrome. Measured from the DOM (`getBoundingClientRect` and computed styles), then captured at 3x with CSS zoom 3. Six tiles were stitched into `design-full-3x.png` (1170x2532).
- **App:** simulator `D379DCF1-…` (iPhone 17 Pro, dark), task "Daily repo review" on the stand-in host `127.0.0.1:8933`. The send step used the board's message.
  - FlowDeck screenshots are 1x (402x874). They were used for lossless colour readings.
  - `flowdeck ui simulator record` frames are 3x (1206x2622). They were used for geometry and crops. HEVC frames read about 2 levels darker than the PNGs, so every colour below comes from the 1x PNG unless it is marked as a 3x reading.
- **Positions:** all positions are measured from the top of the sheet, so the two frames can be compared. The design sheet starts at y=96 in a 390x844 frame. The app sheet starts at y=62 in a 402x874 frame.
- **States:** empty (before send), typed, working (agent replying), result (the board's state). Not on the board: after close, and reopen.
- **Excluded data differences:** task times (6:21 PM vs 10:14 AM), "Claude default" vs "Opus 5.5" as the old model (this task had no model set), and "Skip"/"Use" capitals from autocapitalisation.

## Per-component table

| Component / state | Criterion | Result | Notes |
|---|---|---|---|
| Sheet surface | Internal consistency | PASS | One colour, (44,44,46), from the grabber to the bottom in every state. No seams or bands, only a 1-level glass shadow around the composer |
| Sheet surface | Colour token | **FAIL** | App #2C2C2E vs design #1C1C1E. Every surface on the sheet moves one step lighter (D1) |
| Sheet surface | Presentation | PASS (native) | Large-detent system sheet with its top at 62pt. The board puts the sheet at 96 in an older 844pt frame |
| Grabber | Size / position | PASS | 36x5 at sheet+5 (design 36x5 at sheet+6) |
| Grabber | Colour | PASS (native) | (113,113,117) system drag indicator vs #48484A |
| Header icon tile | Size / position / radius | PASS | 34x34 at (16, +23) in both |
| Header icon tile | Fill | FAIL (follows D1) | #3A3A3C vs #2C2C2E |
| Header icon | Glyph | **FAIL** | D2 |
| Header title | Copy / type / colour / position | PASS | "Change task", 17 semibold, white. Cap top at +25.7 (design +26), x=61 in both |
| Header subtitle | Copy / type / colour / position | PASS | 13pt, (161,161,164) vs #A1A1A6. Updates to "Daily repo review · Tue–Fri at 8:00 AM" after the save, same text as the board. Truncates the longer pre-change schedule; the board has the same nowrap ellipsis |
| Close button | Size / position | PASS | 44x44 circle, right inset 16, top +18, same in both |
| Close button | Glyph / colour | **FAIL** | D3 |
| Close button | Fill | FAIL (follows D1) | #3A3A3C vs #2C2C2E |
| Close button | Behaviour | PASS | Closes the sheet. The task view then shows the new schedule (SC11) |
| Note line | Copy / type / colour / centring | PASS | Copy is exact. 12pt, (161,161,164), centred. Text at +80.7 (design +82.7) |
| User bubble | Text type / pitch / padding-x | PASS | 17pt white, 23pt line pitch in both, about 14pt side padding |
| User bubble | Fill | **FAIL** | D4 |
| User bubble | Corner radius | **FAIL** | D5 |
| User bubble | Height / vertical padding | **FAIL** | D6 |
| User bubble | Width | PARTIAL | 334 wide (x 52–386) vs 318 (x 56–374, max-width 290 + 28). The app allows about 16pt more width, so the first line breaks after "Use" instead of "instead." |
| Thread spacing | Gaps between items | **FAIL** | D7 |
| Agent reply | Copy / type / colour / x | PASS | Copy is exact. 17pt white at x=17 |
| Agent reply | Line pitch | PARTIAL | 23pt vs 24pt (`line-height: 24px`) |
| Change card | Container | PASS (except fill) | 370x250.3 vs 358x250.7. The 12pt extra width is the wider screen. Radius matches about 20 (corner profile within 0.3pt). Fill #3A3A3C vs #2C2C2E follows D1, and card minus sheet is +14 (design +16) |
| Change card | Header row | PARTIAL | "Saved · 3 changes", 15 semibold, is exact. Time is 12 medium, (164,164,166) vs #A1A1A6. The check is green (48,215,89) vs #30D158, but larger and heavier (D8) |
| Change card | Field labels | PASS | 12pt (166,166,168) vs #A1A1A6. Rows match within 0.4–2.4pt |
| Change card | Old value | PASS | 15pt, secondary grey, struck through |
| Change card | Arrow | PARTIAL | Glyph 10.4pt wide vs 8.7pt (about 20% bigger). Gaps are the same: old→arrow 9.3 vs 9.6, arrow→new 10.4 vs 10.4 |
| Change card | New value | PASS (type) / **FAIL** (model copy) | 15 semibold white. The Schedule value wraps to its own line and Agent/Model stay inline, as on the board. Model shows the raw id (D9) |
| Change card | Divider | PASS | 0.5pt hairline across the content width, at card+208.6 (design +213) |
| Change card | Next-run line | **FAIL** (copy) | D10. The clock is the SF `clock` symbol instead of the board's hand-drawn clock (native, accepted). Text is (221,221,223) vs #D1D1D6 (+12, minor) |
| Change card | Internal rows | PASS | Every row is within 4pt of the board; total height is the same. Bottom padding is 15 vs 12.7 |
| Composer | Structure | **FAIL** | D11: no mic glyph |
| Composer | Capsule fill / contrast | **FAIL** | D12 |
| Composer | Placeholder colour | **FAIL** | D13 |
| Composer | Send button, resting state | **FAIL** | D14 |
| Composer | Geometry | PARTIAL | Height 50 vs 52. Insets 12 and send circle 36 with about 8 right padding match. Bottom gap is 43pt from the screen bottom vs 30, because the app respects the safe area |
| Empty state | Structure | PASS | Header, note and composer only, as the board implies. Same token deltas as the result state |
| Typed state | Behaviour | PASS (no design) | The field grows to 2 lines and Send turns accent blue |
| Working state | Behaviour / consistency | PASS (no design) | Bubble appears at once, composer clears, Send disables. Three 7pt dots at x=16 animate under the bubble. The reply and card replace them after about 2.5–4 s |
| Result state | Order | PASS | Note, bubble, reply, card, composer: same order as the board |

## Deltas (design vs app, measured)

- **D1. Sheet base token.** Design sheet #1C1C1E (28,28,30); app (44,44,46) #2C2C2E. The tile, close button and card are therefore #3A3A3C in the app vs #2C2C2E in the design. Likely cause: the sheet uses `secondarySystemBackground` and the cards use `tertiarySystemBackground`. Both are one step lighter than the board in an elevated dark sheet.
- **D2. Header icon glyph.** Design: one 4-point star outline, stroke 1.8, ink box 11.4x11pt, #409CFF (65,156,255). App: SF `sparkles`, a filled cluster of 3 stars, ink box 15.4x18.3pt, (0,143,255).
- **D3. Close glyph.** Design: X ink 9.4x9.4pt, #D1D1D6 (209,209,214). App: X ink 12.3x12.3pt (bold 15pt `xmark`), (162,162,165). The app glyph is about 30% bigger and 47 levels dimmer.
- **D4. User bubble fill.** Design #0A6EE0 (10,110,224); app (0,145,255) #0091FF, the system blue. The app bubble is clearly brighter and more cyan.
- **D5. User bubble radius.** Design 20 (inset 8.0pt at 4pt down, flat by 22pt down). App about 13–14 (inset 4.0pt at 4pt down, flat by about 14pt down). The card in the same frame does measure 20.
- **D6. User bubble height.** 2 lines: design 66 vs app 58.7. Ink-to-edge is 15 / 15.3 in the design vs 11.3 / 12.6 in the app. The design's line-height 23 adds half-leading above and below; the app does not.
- **D7. Thread spacing around the bubble.** Note→bubble: design 15 vs app 25.4 (+10.4). Bubble→reply: design 19.7 vs app 27.7 (+8). Reply→card: 20 vs 18.7 (matches). The extra space comes from padding around the reused transcript message view, on top of the 14pt stack spacing.
- **D8. Card check glyph.** Design ink 11.4x8.4pt (stroke 3). App ink 12.7x12.4pt (heavy `checkmark`), about 50% taller.
- **D9. Model new value copy.** Design "GPT-6 Astra"; app "gpt-6-astra" (the raw id). This is the same model, so it is not a data difference: the agent's reply in the same thread says "GPT-6 Astra". The task view chip also shows "gpt-6-astra", so the app has no model display-name formatter at all.
- **D10. Next-run copy.** Design "Next run: Fri, Oct 16 at 8:00 AM"; app "Next run: tomorrow at 8:00 AM" for the same date. The app uses a relative day where the board uses weekday, month and day. Also, app times use a narrow no-break space ("8:00 AM", "6:21 PM") where the board uses a normal space. This last point is minor.
- **D11. Composer mic.** The design has a 20pt mic glyph (#A1A1A6) between the placeholder and Send. The app has none. Note: the house `MessageComposer` has no mic either, so this may need a decision rather than a fix.
- **D12. Composer contrast inverted.** Design capsule #2C2C2E sits +16 levels *lighter* than the sheet, with a 0.5pt white-10% border and a drop shadow. App capsule (33,33,34) is Liquid Glass and sits 11 levels *darker* than the sheet, so it reads as a recessed well instead of a raised field. The board has no glass.
- **D13. Placeholder colour.** Design #8E8E93 (142,142,147); app about (97,97,100), both on the 1x PNG and the 3x frame. The app placeholder is 45 levels dimmer, so it has much less contrast.
- **D14. Send button with an empty field.** Design: #3A3A3C circle with a white arrow (stroke 3) in the board's empty composer. App: (46,46,48) circle with a grey arrow at about (114,114,115), styled as disabled.

## Confirmed correct

- Order and presence of every element in the empty and result states, with no extra elements.
- Header geometry (tile, title, subtitle, close), all copy, and the subtitle update after the save.
- Note copy, size and colour.
- Reply copy and type.
- Card container size and radius, all field labels, old/new styling, wrapping, divider, header copy and time style.
- Card placement after the reply. The card fires from a real save on the host.
- The composer's insets and Send size.
- The sheet surface is free of seams.
- Close dismisses the sheet, and the task view shows the new schedule.

## Carry-overs and unverified

- **Scroll and fade behaviour:** not verified. One exchange does not overflow the thread, so nothing scrolls. On the board the composer floats over a fade (`linear-gradient` to #1C1C1E). In the app the composer sits below the scroll area, so content never passes behind it. Proving this needs more messages, and that would change the stand-in host's chat, so I did not do it.
- **Keyboard-up layout:** not verified. The sim is headless, so no software keyboard appears.
- **Reopen (not on the board):** after Close and reopen, the thread shows the bubble and reply but no "Saved" card. Cards live only in the open sheet. Recorded for the caller; it is not a board delta. Screenshot: `app-07-reopened-1x.png`.
- **Accessibility (not visual, found during capture):**
  - The sheet-level identifier `task_chat_sheet` overrides the inner ones. The text field, Close and Send all report `task_chat_sheet`, so `task_chat_field`, `task_chat_close` and `task_chat_send` cannot be found; I had to tap by coordinates.
  - The bubble and the reply have empty accessibility labels, so VoiceOver cannot read the messages.
- **Host state after this check:** "Daily repo review" on 127.0.0.1:8933 is now Tue–Fri at 8:00 AM, Codex, gpt-6-astra, and its edit chat holds one exchange. Restart the stand-in host to reset it.

## Files

Design: `design-full-3x.png`.

App:
- `app-02-empty-{1x,3x}.png`, `app-03-typed-{1x,3x}.png`, `app-04a-pending-3x.png`, `app-04b-working-3x.png`, `app-05-result-{1x,3x}.png`
- `app-06-after-close-1x.png`, `app-07-reopened-1x.png`
- `app-send-recording.mov` (the send, the working state, and the start of the reply)

Paired crops (design left, app right, both 3x):
- `pair-01-header.png`, `pair-01b-header-empty.png`, `pair-02-note.png`, `pair-03-user-bubble.png`, `pair-04-agent-reply.png`
- `pair-05-change-card.png`, `pair-06-composer-result.png`, `pair-06b-composer-empty.png`, `pair-07-working-state.png`

Whole screen: `full-side-by-side.png` (design | empty | working | result).
