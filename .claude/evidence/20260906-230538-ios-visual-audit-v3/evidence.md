# iOS Visual Evidence Audit

Verdict: PASS
Timestamp: 2026-09-06 23:05–23:11 (local)
Repository: /Users/eugenechan/dev/personal/lfg (iOS project: /Users/eugenechan/dev/personal/lfg/ios)
Simulator: iPhone 17 Pro, iOS 26.3 — `cc-410abeb6`, UDID C926BFC6-0395-445D-AF67-CFB3061961BF
App: com.eugenechan.lfg (scheme LFG, Debug; fixture pid 38046, real-app pid 48228)

## Change Audited

Select-text v3 (`.claude/feature/select-text-sheet.md`, "User Flow (v3)"): MarkdownUI's
original `lfgFlat` rendering is restored (bordered horizontally scrolling table, GitHub code
box, quote bar, lists) and a native `UITextView` is placed inside each paragraph, table
cell and code block so long-press gives native selection scoped to that block. User
bubbles use the same native view. Audited from the running app only; implementer claims
were re-checked, not trusted.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| SC1 — long-press "staging" in first paragraph: highlight + 2 handles + edit menu with Copy | PASS | `02-sc1-longpress-staging.jpg` — "staging" highlighted, two blue handles, menu Copy / Look Up / Translate |
| SC2 — long-press "eugenes-macbook-pro" cell, drag trailing handle into Port column: highlight stays in cell, clamps at "pro"; Copy puts only cell text on pasteboard | PASS | `03-sc2-cell-longpress.jpg` ("macbook" selected), `04-sc2-drag-past-cell.jpg` (handle dragged from x=164 to x=310, selection clamps at "macbook-pro", nothing in Port column), `05-sc2-pbpaste.txt` — Mac pasteboard seeded with `SENTINEL-BEFORE-COPY`, after Copy `pbpaste` = `macbook-pro` |
| SC3 — heading, bold, inline code, link, bullets + nested bullet, numbered list, boxed code block, blockquote all render (no raw markdown) | PASS | `01-launch.jpg` — every element rendered; no `##`, `**`, backticks, pipes or `>` visible |
| SC4 — matches pre-v2 MarkdownUI look: bordered table, semibold header, horizontal table scroll (Status column off-screen right), grey rounded horizontally scrolling code box, bullet on first line of "Restart the Air's server" | PASS | `01-launch.jpg` (bordered table, bold Host/Port header, Status clipped at right edge, bullet on first line of the two-line item, code box clipped), `06-sc4-table-scrolled-right.jpg` (after leftward swipe on table: Status column with healthy / italic *degraded* visible, scroll indicator), `07-sc4-code-scrolled-right.jpg` (code box scrolled to reveal `'scripts/serve-forever.sh'`). Accessibility tree `01-launch-tree.json` shows Status cells at x=392 (screen width 402) and the code text 528pt wide. Compared against `.claude/feature/evidence/select-text-sheet/03-selection-handles-in-table.jpg`: same body font, code chip, link colour, bullet/number layout, quote bar; table now carries MarkdownUI borders and alternating row fill as intended |
| SC5 — user bubble hugs text on accent; tap shows time caption, second tap hides; long-press gives handles | PASS | `01-launch.jpg` (compact blue bubble hugging "What's the state of the hosts?"), `08-sc5-bubble-tap1.jpg` ("9:06 PM" caption shown), `09-sc5-bubble-tap2.jpg` (caption gone), `10-sc5-bubble-longpress.jpg` ("state" highlighted with white handles + Copy menu) |
| SC6 — real app (no fixture, `LFG_SKIP_PUSH=1`), live long transcript: vertical swipe scrolls, one long-press on a live paragraph shows handles | PASS | `13-sc6-real-app-launch.jpg` (hosts Pro + Air green), `14-sc6-session-opened.jpg` (session "Native text selection for copying", bottom of transcript), `15-sc6-after-vertical-swipe.jpg` (downward swipe over the reply scrolled to earlier content, no selection), `16-sc6-live-paragraph-longpress.jpg` ("Checking" selected with two handles + Copy menu) |
| SC7 — tap `runbook` link: Safari opens example.com, app survives, return works | PASS | `11-sc7-link-tapped.jpg` (Safari on example.com with "◀ lfg" back affordance; `flowdeck apps` still lists pid 38046 running), `12-sc7-returned-to-app.jpg` (fixture intact after tapping back) |
| SC8 — unit tests (`SelectableTextTests`) | PASS | `sc8-unit-tests.txt` — `swift test --filter SelectableTextTests`: 15 tests in 1 suite passed, incl. `plainTextIsOneParagraph` |

## Artifacts

All under `/Users/eugenechan/dev/personal/lfg/.claude/evidence/20260906-230538-ios-visual-audit-v3/`:

- `01-launch.jpg`, `01-launch-tree.json`
- `02-sc1-longpress-staging.jpg`, `02-sc1-tree.json`
- `03-sc2-cell-longpress.jpg`, `04-sc2-drag-past-cell.jpg`, `05-sc2-after-copy.jpg`, `05-sc2-pbpaste.txt`
- `06-sc4-table-scrolled-right.jpg`, `07-sc4-code-scrolled-right.jpg`
- `08-sc5-bubble-tap1.jpg`, `09-sc5-bubble-tap2.jpg`, `10-sc5-bubble-longpress.jpg`
- `11-sc7-link-tapped.jpg`, `12-sc7-returned-to-app.jpg`
- `13-sc6-real-app-launch.jpg`, `14-sc6-session-opened.jpg`, `15-sc6-after-vertical-swipe.jpg`, `16-sc6-live-paragraph-longpress.jpg`
- `sc8-unit-tests.txt`

No recordings: every criterion was provable with before/after stills plus the pasteboard read, so none were made.

## Commands

- `flowdeck config get --json`
- `flowdeck simulator list --json`
- `flowdeck run --no-build -S "C926BFC6-…" --launch-env='LFG_SELECT_TEXT_FIXTURE=1 LFG_SKIP_PUSH=1' --json`
- `flowdeck ui simulator session start -S "C926BFC6-…" --json` (session DF037C38)
- `flowdeck ui simulator tap --point X,Y [--duration 0.8] -S "C926BFC6-…"` (long-presses and taps)
- `flowdeck ui simulator swipe --from 164,398 --to 310,392 --duration 1.5 -S …` (handle drag)
- `flowdeck ui simulator swipe --from 330,385 --to 80,385 --duration 0.4 -S …` (table), `--from 330,655 --to 80,655` (code box)
- `printf SENTINEL | pbcopy` → tap Copy → `pbpaste`
- `flowdeck apps --json`
- `flowdeck run --no-build -S "C926BFC6-…" --launch-env='LFG_SKIP_PUSH=1' --json`
- `swift test --package-path ios/LFGCore --filter SelectableTextTests`
- `flowdeck ui simulator session stop -S "C926BFC6-…" --json`

## Notes

- All taps used coordinates (the native text views expose no accessibility labels in the
  tree — `AXLabel` is empty for every `StaticText`), so positions came from the caller's
  layout map plus the frame geometry in `01-launch-tree.json`.
- The handle drag was a synthetic `swipe` starting on the trailing handle; it moved the
  selection end (from "macbook" to "macbook-pro"), so the gesture was real, and the clamp
  is proven by both the screenshot and the pasteboard read.
- The saved FlowDeck config points at UDID E0DC8228 (Shutdown); the guard accepted the
  caller's session sim C926BFC6 and all work ran there. One command using a shell variable
  for `-S` was blocked by the guard, which created and booted an extra sim
  `cc-410abeb6-ab0cd180` (8C8AE913-CB81-4015-9B42-415DA7063492); it was not used and was
  not deleted.
- SC6 was run on a live session that was actively streaming; the transcript shifted by a few
  points between the long-press and the capture, which is expected and did not affect the
  result.
- Residual risk: not verified on iPad or on a physical device; the pasteboard read relies on
  simulator→Mac pasteboard sync (it worked, sentinel replaced).
