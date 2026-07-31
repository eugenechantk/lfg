# Verification evidence — per-session Live Activity widgets

**Date:** 2026-07-31 · **Device:** iPhone 17 Pro simulator (`E0DC8228-3248-4630-8929-FBC5DFC6AE6D`)
**Design ground truth:** `ios/design/claude-design-20260731/4a-live-activity-ground-truth.jpg` (screen 28)

All verification below was run by Claude independently, not taken from Codex's report.

## Automated

| Check | Command | Result |
| --- | --- | --- |
| Swift model/unit | `cd ios/LFGCore && swift test` | **151 tests, 0 failures** |
| Server push reducer | `bun test src/push/` | **49 pass, 0 fail** |
| Project generation | `cd ios && xcodegen generate` | OK |
| App + widget build | `flowdeck build -w LFG.xcodeproj -s LFG -S "iPhone 17 Pro"` | **Build Completed** |

The build was run in an **isolated worktree** at `HEAD` + only the live-activity
changeset. Necessary because the shared working tree carries two other agents'
in-flight work (session-list restyle, new-session view) which fails to compile
(`SessionListView.swift:513 — no member 'newSessionPresentation'`). That failure is
**not** from this work.

## Visual — each card verified against screen 28

Seeded via `LFG_LA_MOCK=<variant>`, captured on the lock screen.

| State | Screenshot | Result |
| --- | --- | --- |
| working | `ios/design/claude-design-20260731/app-lockscreen-final.png` | **Match** — white glyph + blue dot, green "Working", `· lfg`, host right-aligned, 2-line title, `Running xcodegen` + `1m` |
| blocked | `ios/design/claude-design-20260731/app-card-blocked.png` | **Match** — orange asterisk on `#3A2A22` tile, orange "Needs input", `· inbox`, `Waiting on your reply`, blue **Reply** pill |
| finished | `ios/design/claude-design-20260731/app-card-finished.png` | **Match** — "Finished" secondary, `· lfg`, `Air`, green `+142`, red `−38`, `· 6 Files`, grey **Review** pill |

## Defects found and fixed during verification

1. **Type ramp off by 1 pt (my spec's error, inherited by Codex).** The spec's
   "Nearest SwiftUI" column mapped the design's 14 pt labels to `.subheadline`,
   which is **15 pt**. The status label used an explicit 14 pt while the directory
   tag, footer, pill and elapsed used 15 pt — mismatched sizes in the same row.
   Fixed in `SessionActivityViews.swift` (explicit `.system(size:14)`) and the spec
   table corrected with a warning note.
2. **Build break: color tokens unreachable in `ShapeStyle` position.** Tokens were
   declared as `extension Color { static let … }`, which does not resolve in
   `.foregroundStyle(.lfgX)`. Added an `extension ShapeStyle where Self == Color`
   forwarding layer; zero call-site changes.
3. **Mock harness aborted after the first activity.** One `do/catch` wrapped the
   whole request loop, so a single throw silently skipped the remaining variants —
   only the working card ever appeared. Moved the `try/catch` inside the loop, added
   a 400 ms inter-request pause and per-request logging. All three now start:
   `[LFG_LA_MOCK] started mock-working / mock-blocked / mock-finished`.

## Resolved — per-session confirmed by Eugene; cap raised to the measured ceiling

Eugene reaffirmed the per-session architecture after the HIG concern below was
raised: **one Live Activity per running / needs-input / recently-finished session.**
That is the shipped behavior.

The cap was raised **3 → 5**, and the number is now measured rather than assumed.
`LFG_LA_MOCK=stress8` seeds N synthetic activities one at a time:

```
[LFG_LA_MOCK] started mock-stress-1 … mock-stress-5
[LFG_LA_MOCK] FAILED mock-stress-6: targetMaximumExceeded
[LFG_LA_MOCK] FAILED mock-stress-7: targetMaximumExceeded
[LFG_LA_MOCK] FAILED mock-stress-8: targetMaximumExceeded
```

So ActivityKit's hard per-app ceiling is **5**, and exceeding it fails outright
rather than degrading. `MAX_CONCURRENT_LIVE_ACTIVITIES` in `watcher.ts` is now an
exported named constant pinned to that, asserted in `watcher.test.ts`. Tests
updated to exercise six candidates against the five-slot ceiling (the lowest
priority — a `finished` session — is the one dropped). `bun test src/push/`:
**49 pass, 0 fail**.

Screenshot with five live: `ios/design/claude-design-20260731/app-five-activities.png`.
iOS collapses same-app Live Activities into a **stack** on the Lock Screen, showing
the top card with the others behind it. Because the server orders
`blocked > working > finished`, the card on top is always the most urgent session.

## CONTEXT — the design's 3-card stack is not literally what iOS renders

Screen 28 depicts **three Live Activity cards stacked simultaneously** on the Lock
Screen. That is not reproducible:

- All three activities start successfully (confirmed in the log), but **only one
  renders on the Lock Screen at a time.** Swiping the activity region does not
  expand a stack. (A regular notification *did* stack below it, so this is specific
  to Live Activities, not the capture.)
- Apple's Live Activities HIG explicitly recommends against this architecture:
  > "Let people track multiple events efficiently with a single Live Activity.
  > Instead of creating separate Live Activities people need to jump between to
  > track different events, prefer a single Live Activity that uses a dynamic
  > layout and rotates through events."
  > — [Apple HIG, Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities)

**Consequence:** the per-session widgets work and each matches the design, but the
user sees one card — the highest-priority session, since the server orders
`blocked > working > finished` and caps at 3. The design's "see all your sessions at
once" promise is delivered by **screen 27** (the aggregate fleet card), which is what
the HIG guidance describes and what the pre-existing implementation did.

Not resolved here because it is a product decision, not an implementation defect.
Simulator-only finding for the stacking behavior — worth one device confirmation
before acting on it.
