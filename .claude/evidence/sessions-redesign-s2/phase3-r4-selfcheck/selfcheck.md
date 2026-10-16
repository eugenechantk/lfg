# Self-check after verifier round 3 (2026-10-16)

Round 3: session sheet, Subagents and Files & links PASS; terminal FAIL (D1–D4), sign-in browser
FAIL (E1). Fixes and my measurements (board / app, points). Terminal measured on the scratch rig
with a `W` ruler line (`printf` of 68 W) in plain `sh`.

| Finding | Fix | Board | App after |
|---|---|---|---|
| D1 type size | 12pt (was 13) | 7.225 pt/char | 7.27 pt/char |
| D1 line spacing | SwiftTerm patch 5: `lineHeightMultiple = 1.45`, text centred in the row | 17.4 pt rows | 17.4 (ink tops 17.33–17.67 apart) |
| D1 glyph in row | baseline from half-leading | "l" top 3.17, baseline 12.5 below the row top | 4.2 / 13.2 (+0.7) |
| D1 bottom gap | whole rows sit on the bottom edge; the remainder goes above the first row | last line 10 above the key row | 10.3 (Fit and Wide) |
| D2 Wide | Wide = 10.5pt type on a 1.45 line, fitted to the width (was a 120-column grid scrolled sideways) | 6.32 pt/char, 15.225 rows | 6.29, 15.0–15.33 |
| D3 caret | steady block, #D1D1D6, text-height (patch 5) | (209,209,214), 6.7×13.7, 1.7 below the row top | 208 on all 22 frames over 2 s, 7.3×14.3, 1.4 below |
| D4 extra key | "-" removed | … ~ ⌘V ⌨ | … ~ ⌘V ⌨ |
| E1 disabled arrows | `.allowsHitTesting` instead of `.disabled` (which also faded the fill) | fill (44,44,47), disabled arrow 105 | (42,42,45), 109 |

Column counts follow the width: Fit 50 columns, Wide 58 (the board's 366pt shows 50 and 57).

Note from round 3: the Host row read "Eugenes-MacBook-Pro" without "move to …" because the simulator
then had three hosts (test server, Pro, Air); `SessionSheetModel.HostRow` shows "move to X" for one
other host and a list for several. Data-driven, as designed.

Changed: `ios/Vendor/SwiftTerm` (patch 5 + key row, `PATCHES.md`), `ios/LFG/TerminalScreen.swift`
(font, line height, caret, Wide, bottom-aligned rows; the sideways-scroll code is gone),
`ios/LFG/PhoneSignInView.swift` (arrow buttons).

## After verifier round 4 (terminal: one delta, sign-in PASS)

- G1 keyboard key: the board's own icon, drawn from its SVG (keyboard + chevron), replaces the SF Symbol.
  Icon ink board 20.0 × 15.3 / app 20.0 × 15.33, centred in the 44 × 36 key (`keyboard-key-open.png`).
- The key now does what the board's does: "Hide keyboard" / "Show keyboard" with the chevron flipping
  (it used to swap in SwiftTerm's F-key panel). Hidden keeps the row on screen: bar bottom board 840 /
  app 840 (`keyboard-hidden.png`); "Show keyboard" returns the row to the open position
  (`keyboard-shown-again.png`). Below the hidden row iOS draws its keyboard backdrop (23,23,25) with
  rounded corners where the board shows the page (#0B0B0D): iOS sets any input view on that backdrop.
- Key row top border 0.5pt (board 0.5px).
- Sign-in arrows: `.disabled` is back (VoiceOver dims them) with a button style that does not fade the
  fill: fill (42,42,45), disabled arrows 105–107 (board 44 / 102–105). AXe reports `enabled: true`
  for every SwiftUI `.disabled` control here, the session sheet's dimmed Browser preview tile included,
  so its "enabled" field is not evidence either way.
