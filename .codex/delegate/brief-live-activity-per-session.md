# Delegation Brief: per-session Live Activity widgets (lfg iOS)

**Goal:** Replace lfg's single aggregate "fleet" Live Activity with **one Live Activity per session**, matching the approved Claude Design artboard `4a` / screen `28-live-activity-per-session`.

## Read this first — it is the spec

`.claude/live-activity-per-session/component-breakdown.md` in this repo. It contains the
exact design tokens (colors, type ramp, metrics), the component-by-component breakdown with
source references, the data model, the server changes, and the build order. **Follow it
literally** — the numbers in it were measured from the design source, not estimated.

**Rendered design ground truth:** `ios/design/claude-design-20260731/4a-live-activity-ground-truth.jpg`
(screen 28 is the right-hand phone; screen 27 on the left is **not** being built).
To re-render: `cd ios/design/claude-design-20260731 && python3 -m http.server 8791`
→ `http://localhost:8791/LFG%20iOS%20Baseline.dc.html`, artboard `4a`.

## Constraints

- **`ios/project.yml` is the source of truth**, never `LFG.xcodeproj`. After adding files:
  `cd ios && xcodegen generate`. Direct `.xcodeproj` edits get clobbered.
- **Non-UI logic goes in `LFGCore` with a test.** The app/widget targets stay a thin shell.
  This is why `swift test` can verify the model without a simulator — keep it that way.
- **Lenient decoding is mandatory** for anything on the wire: every field optional with a
  default plus a custom `init(from:)`. Match `LFGCore/Sources/LFGCore/Models.swift`.
- **Swift 6, strict concurrency complete.** Everything crossing an actor boundary is `Sendable`.
- **Server is Bun + TypeScript.** Use `bun test`, not npm/vitest.
- **Lock-screen height ceiling is ~160 pt.** The card budgets ~126 pt. Do not add a fourth
  row — overheight content center-clips and silently drops the header.
- **Do NOT touch:** `SessionStore.swift`, `SessionListView.swift`, `SessionDetailView.swift`,
  `RootView.swift`, or anything under `src/` outside `src/push/` and the two live-activity
  route handlers in `src/commands/serve.ts`. Other agents are working in this repo
  concurrently; keep the diff tight and additive.
- **Do not commit or push.** Leave the work in the working tree.

## Scope decisions already made (do not revisit)

1. **Screen 28 only** — per-session widgets. Screen 27's aggregate fleet card is out of scope.
   The existing fleet activity is replaced, and `FLEET_ACTIVITY_KEY` / `listFleetUpdateTokens`
   are retired.
2. **Directory only; everything else degrades.** `· lfg` / `· inbox` comes from the `cwd`
   basename (already on the wire). The diff-stat footer (`+142 −38 · 6 Files`) and the
   working subtitle (`Running xcodegen`) have **no server source** — ship them as optional,
   currently-nil fields so the views degrade now and light up for free later. Do **not**
   invent a `git diff` call or a tool-line scraper; that is explicitly out of scope.
   The exact degrade rules are the table in §2 of the spec — implement them as written.

## Verification (run these; they are the definition of proof)

```bash
cd ios/LFGCore && swift test          # model decode, state mapping, elapsed formatting
cd /Users/eugenechan/dev/personal/lfg && bun test src/push/   # per-session reducer
cd ios && xcodegen generate           # after adding any file
```

Then build the app + widget extension. **Use FlowDeck (`flowdeck`) — never raw `xcodebuild`,
`xcrun`, `simctl`, or `devicectl`.** Verify the widget visually on an **iPhone 17 Pro**
simulator lock screen with `LFG_LA_MOCK=1`, which must seed exactly three activities reproducing
screen 28 (working / needs-input / finished, using the design's own strings).

## Definition of done

- [ ] `LFGSessionAttributes` exists in `LFGCore` + `ios/Shared`, lenient-decoding, with tests
      covering: absent optional fields, unknown `state` strings, and the `finished` state.
- [ ] `SessionActivityViews.swift` implements every atom/content component in spec §2 at the
      exact tokens in §1, with the accessibility identifiers listed in spec §5.
- [ ] `LFGSessionActivityWidget` renders the lock-screen card and a Dynamic Island derived
      per spec §2, and no longer references `LFGFleetAttributes`.
- [ ] The three footer degrade rules (working / blocked / finished) behave exactly as the
      table specifies, including the static `"Waiting on your reply"` for blocked.
- [ ] Reply and Review pills deep-link to `lfg://session/<sid>`.
- [ ] Server: `liveactivity.ts` emits `attributes-type: "LFGSessionAttributes"` with
      `attributes: { sessionId }`; `watcher.ts` has `reduceSessionLiveActivities` keyed per
      session with the documented selection, **cap-at-3 (and a log line naming what was
      dropped — no silent truncation)**, and start/update/end transitions including the
      `now + 480` dismissal date for finished sessions.
- [ ] `POST /api/push/live-activity/update-token` accepts an optional `sessionId`; omitting it
      still succeeds (an older client must not 400).
- [ ] `LiveActivityManager` tracks `Activity<LFGSessionAttributes>` and registers each update
      token **with its `sessionId`**; `LFGClient.registerLiveActivityUpdateToken` gains the parameter.
- [ ] `swift test` and `bun test src/push/` both pass. Paste the real output.

## Report back

Files changed, the actual verification command output (not a summary), a screenshot path for
the simulator lock screen, and anything you could not complete and why.
