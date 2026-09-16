# iOS Visual Evidence Audit

Verdict: PASS
Timestamp: 2026-09-06 22:09 HKT
Repository: /Users/eugenechan/dev/personal/lfg (iOS project: /Users/eugenechan/dev/personal/lfg/ios)
Simulator: cc-410abeb6-a72fe2a6 — iPhone 17 Pro, iOS 26.3, UDID 13E727D1-E3AD-4AA0-B27D-AB1498EDDD02 (assigned by the FlowDeck per-session guard; the UDID given in the brief was refused, so the app was rebuilt with `flowdeck run`)
App: com.eugenechan.lfg (scheme LFG, Debug, launched with `LFG_SELECT_TEXT_FIXTURE=1 LFG_SKIP_PUSH=1`)

## Change Audited

"Select Text" sheet for transcript messages (feature doc: `.claude/feature/select-text-sheet.md`).
Long-pressing an assistant response or a user bubble shows a context menu with
**Select Text** and **Copy**. Select Text opens a sheet with a native selectable
`UITextView` rendering the message (headings, bold, inline code, links, nested
lists, code block, blockquote, GFM table as tab-aligned rows). Toolbar: Copy All
(leading, icon) and Done (trailing). Menu Copy copies raw markdown; Copy All
copies rendered text. Audited entirely from the running app via the DEBUG
fixture (`SelectTextFixture`), which drives the real `TranscriptMessageView` path.

## Success Criteria

| Criterion | Result | Evidence |
|-----------|--------|----------|
| SC1: Long-press on the assistant response shows a context menu with "Select Text" and "Copy" | PASS | `02-sc1-context-menu.jpg` (menu + 6-line compact preview); `sc1-sc2-longpress-select-drag.mov` 0–5s |
| SC2a: "Select Text" presents a sheet; long-press on a word shows the native selection overlay (highlight + two drag handles + edit menu with Copy) | PASS | `04-sc2-selection-overlay.jpg` — "healthy" highlighted, two handles, Copy / Look Up / Translate; `.mov` ~15–72s |
| SC2b: Dragging a selection handle extends the highlight across at least one more word / cell boundary | PASS | `05-sc2-handle-dragged.jpg` (start handle moved: highlight spans "Status" → "eugenes-macbook-pro", crossing the header/data row boundary); `06-sc2-handle-dragged-2.jpg` (end handle moved: highlight spans "healthy" → "eugenes-macbook-air" → "8766", crossing two cell boundaries); `08-selection-copy-pasted.jpg` — Copy from that selection pasted as `eugenes-macbook-air<TAB>8766` (tab-separated cells) |
| SC3: heading, bold, inline code, bullets + nested bullet, numbered list, fenced code block, blockquote, link all rendered (no raw syntax) | PASS | `03-sc3-sc4-sheet-rendered.jpg` — "Deploy summary" bold/large, **staging** bold, `lfg serve --port 8766` and `tmux` monospace with background, "runbook" blue link, "•" bullets with indented nested "•", "1./2." list, monospace code block without fences, grey quote without ">" |
| SC4: table renders as rows with aligned columns (Host / Port / Status header, two data rows) | PASS | `03-sc3-sc4-sheet-rendered.jpg` — header row bold, Port and Status columns aligned across all three rows; "degraded" italic |
| SC5a: Copy All → Done → paste yields rendered text | PASS | `09-sc5-after-copy-all.jpg`, `10-sc5-copy-all-pasted.jpg` — pasted tail reads `•  Re-run the smoke test / 1. Pull main / 2. Build / ssh … / Do not restart the Pro; it owns the tunnel.` (no fences, no ">", rendered markers) |
| SC5b: menu Copy → paste yields raw markdown (contains `**staging**` or a `\|` row) | PASS | `12-sc5-menu-copy-pasted.jpg` (` ```sh ` fences, `> ` quote), `13-sc5-menu-copy-pasted-head.jpg` (`## Deploy summary`, `**staging**`, backticks, `[runbook](https://example.com/runbook)`) |
| SC6a: user bubble still toggles a timestamp caption on single tap | PASS | `14-sc6-before-tap.jpg` (no caption) → `15-sc6-after-single-tap-timestamp.jpg` ("Sep 6, 2025 at 3:20 AM" caption) → `18-sc6-timestamp-toggled-off.jpg` (second tap hides it); `sc6-user-bubble-tap-and-longpress.mov` |
| SC6b: long-press on the user bubble shows the same Select Text / Copy menu | PASS | `16-sc6-user-bubble-context-menu.jpg`; `17-sc6-user-bubble-sheet.jpg` (Select Text from the bubble opens the sheet with the user text); `.mov` |

## Artifacts

All under `/Users/eugenechan/dev/personal/lfg/.claude/evidence/20260906-215937-ios-visual-audit/`:

- `01-launch.jpg` — fixture at launch (user bubble, markdown reply with MarkdownUI table, paste field)
- `02-sc1-context-menu.jpg` — assistant long-press menu
- `03-sc3-sc4-sheet-rendered.jpg` — Select Text sheet, full rendering
- `03-sheet-tree.json` — accessibility tree while the sheet is up (only the sheet grabber is exposed; see Notes)
- `04-sc2-selection-overlay.jpg` — native selection on "healthy"
- `05-sc2-handle-dragged.jpg`, `06-sc2-handle-dragged-2.jpg` — after handle drags
- `07-after-done.jpg` — sheet dismissed by Done
- `08-selection-copy-pasted.jpg` — selection Copy pasted into the fixture field
- `09-sc5-after-copy-all.jpg`, `10-sc5-copy-all-pasted.jpg` — Copy All round trip
- `11-sc5-after-menu-copy.jpg`, `12-sc5-menu-copy-pasted.jpg`, `13-sc5-menu-copy-pasted-head.jpg` — menu Copy round trip (field scrolled to tail and head)
- `14-sc6-before-tap.jpg`, `15-sc6-after-single-tap-timestamp.jpg`, `16-sc6-user-bubble-context-menu.jpg`, `17-sc6-user-bubble-sheet.jpg`, `18-sc6-timestamp-toggled-off.jpg` — user bubble behaviour
- `sc1-sc2-longpress-select-drag.mov` (75.8s) — assistant long-press → menu → Select Text → long-press "healthy" → overlay
- `sc6-user-bubble-tap-and-longpress.mov` (15.1s) — user bubble single tap (caption) and long-press (menu)

## Commands

```
flowdeck config get --json
flowdeck run -S "13E727D1-E3AD-4AA0-B27D-AB1498EDDD02" --launch-env='LFG_SELECT_TEXT_FIXTURE=1 LFG_SKIP_PUSH=1' --json     # full build + install + launch
flowdeck ui simulator session start -S "13E727D1-…" --json                                                             # session A728BF0F
flowdeck ui simulator record -o <evidence>/sc1-sc2-longpress-select-drag.mov -t 75 --force -S "13E727D1-…" --json
flowdeck ui simulator tap --point 120,300 --duration 0.8 -S …                                                          # SC1 long-press
flowdeck ui simulator tap "Select Text" -S …
flowdeck ui simulator tap --point 310,276 --duration 0.8 -S …                                                          # long-press "healthy"
flowdeck ui simulator touch down 286,258 / touch up 215,270 -S …                                                       # drag start handle
flowdeck ui simulator touch down 221,291 / touch up 345,278 -S …                                                       # drag end handle
flowdeck ui simulator tap --point 95,352 -S …  (selection-menu Copy); tap --point 349,100 (Done)
flowdeck ui simulator tap --point 200,747 -S … ; swipe --from 200,480 --to 200,180 ; tap --point 200,523 ; tap "Paste" ; hide-keyboard
flowdeck run --no-build -S … --launch-env='…' --json                                                                   # relaunch between SC5a / SC5b / SC6 to reset the paste field
flowdeck ui simulator tap --point 37,100 -S …  (Copy All) ; tap --point 349,100 (Done)
flowdeck ui simulator tap "Copy" -S …                                                                                  # context-menu Copy
flowdeck ui simulator record -o <evidence>/sc6-user-bubble-tap-and-longpress.mov -t 30 --force -S … --json
flowdeck ui simulator tap --point 260,196 -S … ; tap --point 260,196 --duration 0.8 -S …                               # SC6
flowdeck ui simulator session stop -S … --json
```

## Notes

- **Different simulator than the brief.** The PreToolUse guard refused
  `C926BFC6-…` and created/booted `13E727D1-…` for this session, so the app was
  rebuilt from the current working tree with `flowdeck run` (build succeeded).
  Evidence therefore reflects the tree as of 22:00 HKT, not the implementer's
  earlier install.
- **Coordinate taps were used** for the long-presses, the sheet toolbar (Copy All
  37,100 / Done 349,100 — not in the accessibility tree), the selection-menu Copy,
  and the paste field (`fixturePasteField` was not resolvable by id via
  `find`; the tree shows it as an unlabeled `TextField`). "Select Text", "Copy"
  (context menu) and "Paste" (callout) were tapped by label.
- **Handle drags with synthetic input.** `swipe` did not move a selection handle
  (no-op, same frame as `04`). `touch down` on the knob followed by `touch up` at
  the destination did move it, but idb emits no intermediate move events, so the
  resulting anchor placement is a jump rather than a smooth drag — the selection
  in `05` re-anchored to "Status → eugenes-macbook-pro" instead of the expected
  "…→ healthy". This is a limitation of the input path, not the feature: the
  highlight extended across cell/row boundaries on both drags and the copied
  text was tab-separated (`08`). On a device or with a real finger the drag is
  continuous.
- **`selectableTextView` accessibility id could not be confirmed from the tree.**
  While the sheet is presented the FlowDeck/idb tree exposes only the "Sheet
  Grabber" button (see `03-sheet-tree.json`); the UITextView's identifier is a
  source-level claim I could not verify at runtime. Its presence does not affect
  any of SC1–SC6 as written.
- **Recording lengths.** The SC1/SC2 recording (75s) covers the menu, sheet,
  and long-press overlay but ended before the handle drags (those are proven by
  stills `05`/`06` and the pasted result `08`). The SC6 recorder returned after
  ~15s despite `-t 30`; the clip still contains the untapped bubble, the caption
  after the single tap, and the long-press menu.
- **Copy All paste shows the tail only** (`10`): the field is `lineLimit(1...6)`
  and the pasted text is ~15 lines, so the visible portion is the last six
  lines. What is visible is unambiguously rendered (bullet/number markers, no
  fences, no `>`), which is the discriminating difference from `12`/`13`.
- Not audited: real transcript rows on a live host (the fixture drives the same
  `TranscriptMessageView` but not `SessionDetailView`'s scrolling list), iPad,
  Dark Mode, Dynamic Type, and long tables whose cells wrap (the decision log
  says alignment breaks on that row only).
