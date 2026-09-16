# iOS Visual Evidence Audit

Verdict: PASS
Timestamp: 2026-09-06 22:29 – 22:48 (local, Eugenes-MacBook-Pro)
Repository: /Users/eugenechan/dev/personal/lfg (iOS project: /Users/eugenechan/dev/personal/lfg/ios)
Simulator: iPhone 17 Pro, iOS 26.3 — `cc-410abeb6`, UDID `C926BFC6-0395-445D-AF67-CFB3061961BF`
App: com.eugenechan.lfg (scheme LFG, Debug; fixture launch pid 57253, real-app launch pid 89790)

## Change Audited

v2 of in-place text selection: assistant replies and user bubbles in the transcript are
rendered by `SelectableProseView` (a non-scrolling `UITextView` per message,
`ios/LFG/SelectableProse.swift`, wired in `ios/LFG/Components.swift`). Native long-press
selection with handles and the edit menu replaces the rejected v1 "Select Text" sheet.
Tables are drawn as a bordered grid inside the text view; code blocks get a rounded box;
user bubbles are white-on-accent, hug their content, and toggle a sent-time caption on tap.

Judged only from the running app. Implementer claims were re-checked, not trusted.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| SC1 Long-press a word in an assistant reply → highlight, two handles, edit menu with Copy | PASS (fixture + live row) | `02-sc1-longpress-staging.jpg` ("staging" highlighted, 2 handles, Copy · Look Up · Translate ›), `02-sc1-tree.json` (labels Copy/Look Up/Translate), `sc1-longpress.mov`; live row: `47-sc1-live-longpress.jpg` + `47-sc1-live-tree.json` ("Applied" selected in the real "Consolidate codex to bun" transcript), `sc6-live-swipe-and-longpress.mov` |
| SC2 Drag a handle across a table cell boundary into the following paragraph/list; Copy places that range on the pasteboard | PASS (copy proven via pasteboard; paste-into-field blocked by simulator, see Notes) | Interpolated drag: `38-sc2-swipe-highlight.jpg` (handles at "\|staging" … "degraded\|", crossing paragraph → all 9 table cells) matches `38-sc2-pasteboard.txt` byte-for-byte. Synthetic no-move drag: `36-sc2-drag-highlight.jpg` / `36-sc2-pasteboard.txt` — copied range runs "check it, or read the runbook." → table rows → "Next steps:" → "• Restart the", i.e. out of the table into the next paragraph and first bullet. `sc2-handle-drag.mov` |
| SC3 Markdown structure rendered natively (heading, bold, inline code, link, bullets + nested, numbered, fenced code box, blockquote); no raw syntax | PASS | `01-launch-fixture.jpg`: "Deploy summary" heading, **staging** bold, `lfg serve --port 8766` / `tmux` inline code, blue "runbook" link, bullets with nested "confirm tmux…", 1./2. numbered list, `ssh …` in a rounded grey box, "Do not restart the Pro…" as a grey quote; no `#`, `**`, backticks, `>`, `|` or `[]()` visible |
| SC4 GFM table renders as a bordered grid (header fill, alternating rows, column lines, row lines) | PASS | `01-launch-fixture.jpg` / `11-reset-top.jpg`: Host/Port/Status header with grey fill, row 1 white, row 2 grey, vertical lines between the three columns, horizontal lines between rows |
| SC5 User bubble: compact accent bubble hugging its text; tap shows time caption, second tap hides; long-press gives selection handles | PASS | `31-sc5-tap1-caption.jpg` (bubble spans x≈134–385 of 402pt, not full width; "9:06 PM" caption appears), `32-sc5-tap2-hidden.jpg` (caption gone; tree has no time label), `33-sc5-longpress.jpg` + `33-sc5-longpress-tree.json` ("state" highlighted with two handles, Copy · Look Up · Translate), `sc5-user-bubble.mov` |
| SC6 Plain vertical swipe over a reply scrolls the transcript instead of selecting (real app, tall transcript) | PASS | Real app, no fixture env, session "Consolidate codex to bun": `44-sc6-before-swipe.jpg` (bottom of transcript) → swipe down → `45-sc6-after-swipe-down.jpg` (earlier bullets now visible, no highlight, no menu in tree) → swipe up → `46-sc6-after-swipe-up.jpg` (back at bottom). `sc6-live-swipe-and-longpress.mov` |
| SC7 Tapping the `runbook` link opens the URL without crash or selection | PASS | `40-sc7-before-link-tap.jpg` → tap link → `41-sc7-after-link-tap.jpg` (Safari, address bar "example.com", "◀ lfg" breadcrumb), `41-sc7-tree.json` (Application 'Safari'); `flowdeck apps` still lists the app pid 57253 as running after the handoff |
| SC8 Plain text renders unchanged | NOT RE-RUN (unit test per doc: `SelectableTextTests.plainTextIsOneParagraph`) | No UI action required by the doc; not independently re-run here |

## Artifacts

Directory: `/Users/eugenechan/dev/personal/lfg/.claude/evidence/20260906-222930-ios-visual-audit-v2/`

Primary proof
- `01-launch-fixture.jpg` — fixture at launch (SC3, SC4)
- `02-sc1-longpress-staging.jpg`, `02-sc1-tree.json`, `sc1-longpress.mov` — SC1 on the fixture
- `38-sc2-swipe-highlight.jpg`, `38-sc2-pasteboard.txt` — SC2 highlight vs copied text (interpolated handle drag)
- `36-sc2-drag-highlight.jpg`, `36-sc2-pasteboard.txt`, `sc2-handle-drag.mov` — SC2 crossing out of the table into paragraph + bullet
- `31-sc5-tap1-caption.jpg`, `32-sc5-tap2-hidden.jpg`, `33-sc5-longpress.jpg`, `33-sc5-longpress-tree.json`, `sc5-user-bubble.mov` — SC5
- `42-sc6-real-app-launch.jpg`, `43-sc6-session-open.jpg`, `44…46-sc6-*.jpg`, `sc6-live-swipe-and-longpress.mov` — SC6 on the real app
- `47-sc1-live-longpress.jpg`, `47-sc1-live-tree.json` — SC1 on a live row
- `40-sc7-before-link-tap.jpg`, `41-sc7-after-link-tap.jpg`, `41-sc7-tree.json` — SC7

Investigation trail (paste-into-field attempts and controls; kept for traceability)
- `03`–`10`, `12`–`20` — first two copy/paste attempts; pasteboard-permission alert (`04`, `16`); field never received the paste
- `21`–`27` — control: field's own text "zzqq" Select All → Copy → erase → Paste; paste also never landed (`27-paste-path-result.jpg`), proving the Paste callout press is the blocked step, not the transcript copy
- `28`/`29`, `34`/`35`, `37`, `39` — additional copy samples; `29-`, `35-`, `39-sc2-pasteboard.txt` are the pasteboard reads for each

## Commands

- `flowdeck config get --json` (saved config points at UDID E0DC8228…; the session sim C926BFC6… was used as instructed, passed explicitly with `-S` on every command)
- `flowdeck run --no-build -S "C926BFC6-0395-445D-AF67-CFB3061961BF" --launch-env='LFG_SELECT_TEXT_FIXTURE=1 LFG_SKIP_PUSH=1' --json`
- `flowdeck ui simulator session start -S "C926BFC6-…" --json` (session 2BF7FC0B; `latest.jpg` / `latest-tree.json` read after every action)
- `flowdeck ui simulator tap --point X,Y [--duration 0.8] -S "…"` — taps and long-presses
- `flowdeck ui simulator touch down X,Y` / `touch up X,Y -S "…"` — no-move handle drag and HID presses on edit-menu items
- `flowdeck ui simulator swipe --from X,Y --to X2,Y2 --duration 1.5–2.0 -S "…"` — interpolated (move-event) handle drag; `--duration 0.4` for the SC6 scroll swipes
- `flowdeck ui simulator record -o <mov> -t N --force -S "…" --json` (run in background while driving)
- `flowdeck ui simulator type`, `erase`, `key 42`, `hide-keyboard -S "…"` — paste-path control
- `flowdeck run --no-build -S "C926BFC6-…" --launch-env='LFG_SKIP_PUSH=1' --json` — real app for SC6
- `flowdeck apps --json` — app still running after the SC7 handoff
- `flowdeck ui simulator session stop -S "C926BFC6-…" --json`
- `pbpaste` (macOS) — reads the Mac pasteboard that Simulator.app syncs from the sim; used as the objective reader of what Copy placed on the pasteboard

## Notes

- **SC2 paste-into-field could not be performed in this simulator.** The Paste callout item never inserts, even for the field's own copied text (`27-paste-path-result.jpg`), and every pasteboard change raises an iOS "LFG would like to paste from LFG" permission alert (a side effect of Simulator pasteboard sync bouncing the write back). Allowing the alert by coordinate did not change the outcome. The copy half is instead proven via the synced Mac pasteboard, which updated on every Copy (control "qqzz" → drag range), so the criterion's substance — the selected range crosses the table boundary and Copy captures that range — is established. A paste on a real device is the only residual gap.
- **Synthetic no-move drags can desync the drawn highlight from the real range.** With `touch down`/`touch up` (no move events) the drawn highlight started at "sta|ging" while the copied range started at "check it" (`36-*`). With FlowDeck `swipe` (interpolated moves, like a finger) the highlight and copied text matched exactly (`38-*`). This is a tooling artifact of the no-move gesture, not an app defect; a real finger sends move events. Future audits should use `swipe --duration ≥1.5` for handle drags.
- The edit menu does not always re-appear after a synthetic handle drag; a single tap inside the highlight re-summons it without collapsing the selection. FlowDeck label taps on edit-menu/callout items were unreliable; HID `touch down`/`up` at the item's frame centre worked every time (Select All, Copy). Label matching is also substring-based: `tap "Allow Paste"` may hit "Don't Allow Paste" — tap alerts by frame.
- The `selectableProse` accessibility id is not exposed in FlowDeck's tree (the text views are not enumerated as elements); selection proof therefore relies on screenshots plus the Copy/Look Up/Translate menu labels, which only exist when a selection is active.
- A FlowDeck guard misfire created an orphan simulator `cc-410abeb6-a4ee1ba2` (`A06D027F-C2B7-403A-98DC-5400AFAF9002`) when one help lookup ran without `-S`; it was not used. The instructed UDID continued to be accepted for every real command.
- The real app is left open on the "Consolidate codex to bun" session with the word "Applied" selected; nothing was relaunched after the audit.
- SC8 was not re-run (unit-test criterion per the feature doc).
