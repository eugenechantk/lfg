# lfg iOS client — agent instructions

Native SwiftUI client for the `lfg serve` backend. **Read `ios/README.md` first**
for the feature/UX overview; this file is the working-agent's map: where things
live, the conventions to keep, and the traps that have burned past sessions.

> The root [`.claude/CLAUDE.md`](../.claude/CLAUDE.md) covers the whole repo
> (server, sendq, concurrent-session hazards). This file is iOS-only.

## Tooling — non-negotiable

- **Use FlowDeck (`/flowdeck`) for everything Apple:** build, run, test, boot
  simulators, install on device, capture logs, UI-automate. Never call
  `xcodebuild`, `xcrun`, `simctl`, `devicectl`, `xcode-select`, or `instruments`
  directly, and never hand-parse `.xcodeproj`.
- **`project.yml` is the source of truth**, not `LFG.xcodeproj`. Edit `project.yml`,
  then `cd ios && xcodegen generate`. Changes made directly in the Xcode project
  will be clobbered.
- **Don't `cd` between FlowDeck commands** — its simulator guard keys off the cwd.
  Use the literal UDID it returns (see memory `flowdeck-sim-guard-cwd`).

## Layout

| Path | What |
| --- | --- |
| `LFG/LFGApp.swift` | `@main` entry; `AppSettings` (persisted host/owner/group mode/filter) |
| `LFG/SessionStore.swift` | **The state core.** `@MainActor @Observable` — reduces REST snapshots + SSE deltas into per-session state. Most logic lives here. |
| `LFG/RootView.swift` | Adaptive `NavigationSplitView`; host gating; notification-selection + scenePhase wiring |
| `LFG/SessionListView.swift` | Grouped/filtered list, section headers, status badge |
| `LFG/SessionDetailView.swift` | Live transcript, composer, prompt panel, toolbar (model/assign/rename/stop/end), auto-scroll |
| `LFG/NewSessionView.swift` | Agent/model/dir selectors + kickoff composer |
| `LFG/MessageComposer.swift` | Reusable input bar (multiline grow, attach, send); `GlassPanel` |
| `LFG/Components.swift` | Transcript bubbles, thinking block, tool lines, prompt panel, pending/queue strips, usage |
| `LFG/RichContent.swift` | Host-file URL resolution, media scanning, markdown (MarkdownUI), full-screen viewer (image zoom / PDF) |
| `LFG/PushManager.swift` | APNs lifecycle + `AppDelegate`; side-effecting shell around `LFGCore/Push` |
| `LFG/{Theme,SettingsView}.swift` | Visual helpers; host config / notifications / directories UI |
| `LFGCore/Sources/LFGCore/Models.swift` | All Codable API types (lenient decoding) |
| `LFGCore/Sources/LFGCore/LFGClient.swift` | Stateless async HTTP/SSE client (Sendable) |
| `LFGCore/Sources/LFGCore/SSEParser.swift` | Incremental SSE parser + frame→`LiveEvent` decoder |
| `LFGCore/Sources/LFGCore/Push.swift` | Pure push-payload parsing + registration state machine |
| `LFGCore/Tests/…` | Unit tests for the above (`swift test`) |

## Conventions

- **Put non-UI logic in `LFGCore`, with a test.** API shapes, parsing, state
  machines, anything reasonable-about without Apple's runtime. The app target is
  the thin SwiftUI/UIKit shell. This is why `swift test` can verify the meat
  without a simulator — keep it that way.
- **`SessionStore` is the single source of truth.** Views read its observable
  state; they don't hold their own session/network state. Per-session data is
  keyed by `sessionId` (`transcripts`, `prompts`, `busy`, `queues`,
  `pendingSends`). Steering actions go through `store.run(label:)` → refresh.
- **Lenient decoding.** Every model field is optional with a default and a custom
  `init(from:)`; the server adds/omits fields across versions and a decode must
  not hard-fail. Match this when adding fields.
- **Swift 6, strict concurrency complete.** Everything crossing actor boundaries
  is `Sendable`. `SessionStore`/`PushManager` are `@MainActor`; `LFGClient` is a
  `Sendable` struct. Parse non-Sendable payloads (e.g. notification `userInfo`)
  off the main actor, then hop with the parsed value.

## Traps (cost real time before — don't rediscover)

- **SSE blank lines are the dispatch boundary.** `URLSession.AsyncBytes.lines`
  *swallows* blank lines, so you'd never dispatch a frame — split raw bytes on
  `\n` yourself (`LFGClient.liveStream` does). And `\r\n` is a **single** Swift
  grapheme, so `firstIndex(of: "\n")` never matches CRLF — split on
  `unicodeScalars` (`SSEParser.feed` does).
- **Live delivery is `HostLink` (one per host) consuming `/api/events?since=`.**
  There is no id-selected stream anymore — do NOT reintroduce per-session stream
  subscriptions or tear a link down for session lifecycle/focus changes (that
  was the old design's biggest self-inflicted-disconnect source). A clean close
  AND a thrown error both land in `HostLink.run`'s retry loop; the cursor makes
  every reconnect lossless. Watchdog subtlety: URLSession's `timeoutInterval`
  (18s, idle-based) covers the response-header phase that the byte watchdog
  can't — a black-holed host accepts TCP and never sends headers.
- **Notification taps must defer the selection onto the next runloop turn.**
  Setting `requestedSelection` synchronously inside UIKit's launch/CATransaction
  snapshot drives a `NavigationSplitView` selection mid-transaction → UIKit throws
  and the app "opens then quits." `openFromNotification` hops a turn on purpose.
- **A cold-launch selection can't mutate `selection` during a view update** —
  it's applied in a post-render `.task` in `RootView`, not inline. Doing it inline
  renders a blank/black screen.
- **Sends must outlive the view.** Use `store.dispatchSend` (takes the
  background-task assertion *synchronously*, retains the task in the store) — not
  a view-owned `.task`. Leaving the view or backgrounding must not drop the send.
- **Optimistic state is reconciled, not authoritative.** Pending sends and
  placeholder (`local-…`) sessions are matched/remapped against the server's
  queue + transcript. When touching that path, preserve the reconcile-by-text and
  `remap(from:to:)` logic or bubbles duplicate / get stuck.
- **Device-only bug? First check the device got the latest build.** A stale
  installed build (works on sim, broken on device) once looked exactly like a code
  bug. Reinstall before theorizing.
- **macOS host has no `/proc`.** CLI/tmux enumeration + the prompt panel depend on
  the server's `src/procinfo.ts` shim. Missing CLI sessions on a macOS host is
  expected, not an app bug.

## Verifying changes

- `cd ios/LFGCore && swift test` for any `LFGCore` change — fast, deterministic.
- **UI-affecting changes must be exercised live** in the simulator/device via
  FlowDeck (tap the real gesture, drive the real transport). A green mocked/unit
  suite is **not** "verified" — see repo memories `verify-ui-by-tapping` and
  `verify-real-seam-not-mocks`. Capture a screenshot/log as evidence.
- This is a **shipping product** (TestFlight) → product tier: use the full
  `/ios-development` workflow for features/bugfixes.

## Concurrency hazard (shared repo)

Multiple lfg agent sessions may edit `ios/` at once. Before editing high-traffic
files (`SessionStore.swift`, central views), check `git status` / `lfg-sessions`
for concurrent work and keep edits minimal and additive to avoid "file modified
since read" breaks.
