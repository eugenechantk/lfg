# Diagnosis: iOS app crashes frequently while backgrounded (2026-08-30)

## Symptom

App crashes "often when I am not using it" — Eugene sees the TestFlight crash prompt
when the app is in the background. TestFlight prompt ⇒ real crash reports exist, not
just silent jetsam eviction.

## Evidence

- **TestFlight crash feedback** (via ASC API `betaFeedbackCrashSubmissions` — see memory
  `testflight-crashes-via-asc-api`): exactly one submission, 2026-07-11, v1.1.0
  (202607110150), iPhone 13 Pro, iOS 26.5. Saved under the session scratchpad
  `testflight-crashes/`; fetch script kept at `.claude/tools/asc_crashes.py`.
- The crash: `EXC_BREAKPOINT`, process role **Non UI** (background launch by
  BGTaskScheduler), crashed thread:
  `BGTaskScheduler _runTask` → thunk → `closure #1 in AppDelegate.application(didFinishLaunchingWithOptions:)`
  → `swift_task_checkIsolated` → `_dispatch_assert_queue_fail` → trap.
- Device `.ips` logs NOT yet pulled (phone locked all session; a watcher is/was armed to
  pull them on unlock). **Confirming the ongoing crashes share this signature is still
  open** — the July log proves the bug, not that it is the only one currently firing.

## Root cause (confirmed, fixed)

`ios/LFG/PushManager.swift` — the BGAppRefresh launch handler registered in
`AppDelegate.didFinishLaunchingWithOptions` is MainActor-isolated by inference
(`AppDelegate` is `@MainActor`; the SDK's `register(forTaskWithIdentifier:using:launchHandler:)`
closure is not `NS_SWIFT_SENDABLE`, so the closure inherits the enclosing isolation —
that's also the only way its synchronous `Self.scheduleAppRefresh()` call compiles).
`using: nil` makes BGTaskScheduler invoke it on its own background queue; the Swift 6
runtime isolation check traps **at closure entry**, before the `Task { @MainActor }`
hop inside can matter. Registration is re-armed on every backgrounding
(`RootView` scenePhase), so every granted background refresh = one crash. Shipped
2026-07-10 (857415c), unchanged until today.

**Fix:** register with `using: .main` — the handler (and its expiration handler, which
runs on the same queue) now executes where its isolation says it must.
`ios/LFG/PushManager.swift:187`.

## Second fix (API-contract violation, same "background crash" presentation)

`SessionStore.enterBackground()` (`ios/LFG/SessionStore.swift`): the `lfg.linger`
background-task expiration handler deferred `endBackgroundTask` into a
`Task { @MainActor }` hop. iOS requires ending the assertion **synchronously** in the
handler; when the main actor is busy the hop misses the window and RunningBoard kills
the process ("background task expired" termination). It also neither cancelled the 25s
sleeper nor invalidated the id, so the assertion could be ended twice.

**Fix:** assertion id moved to a store property (`lingerAssertion`), a single idempotent
`endLingerAssertion()`, and the expiration handler runs synchronously via
`MainActor.assumeIsolated` (expiration handlers are documented to run on the main
thread), cancelling the sleeper so no path double-ends.

## Verification status

- Both fixes compile under Swift 6 strict concurrency (FlowDeck Debug build, green).
- The real seam (an actual BGTask background launch) cannot fire on the simulator;
  live proof requires either a device + LLDB `_simulateLaunchForTaskWithIdentifier`,
  or shipping the TestFlight build and watching the crash prompts stop.
- **Unverified-live until then.** Next concrete steps:
  1. Phone unlocked → pull `.ips` logs, confirm ongoing-crash signatures match.
  2. Ship TestFlight build (needs Eugene's go-ahead), monitor.

## Audit backlog (found by background-path audit; NOT fixed — awaiting crash-log evidence)

Ranked; fix only what the device logs implicate, this is a shipping app:

1. **`didReceiveRemoteNotification` sync has no wall-clock bound** — `backgroundSync`
   (`SessionStore.swift`) loops hosts × 10 pages × 10s timeouts with no deadline or
   cancellation check; the push-wake window is ~30s (watchdog `0x8badf00d`). Fix shape:
   overall `Task` deadline ~20s, return `.newData` with whatever applied.
2. **`BackgroundSender.systemCompletionHandler` has no fallback** — if
   `urlSessionDidFinishEvents` never fires or the MainActor hop is late, the app is
   killed for not calling the handler. Fix shape: timeout fallback that calls it once.
3. **Detached GRDB writes in flight at suspension** (`writeThrough`, `persistCursor`,
   per-line `ConnectionLog.flush`) — `0xdead10cc`-class risk, ranked lower (no app
   group involved).
4. **Unbounded in-memory transcripts, no memory-warning handling** — background jetsam
   with no stack. Fix shape: trim on `.background` / `didReceiveMemoryWarning`.
5. **`BackgroundSender.inflight` keyed by `taskIdentifier`** — identifier collision
   after a background relaunch leaks a continuation and wedges a send assertion.
6. Live Activity observation storm during background sync (cost, not crash);
   stray sleeping Tasks waking the suspended process (cost, not crash).

## Discriminators for the device logs, when they arrive

- `dispatch_assert_queue` / `Incorrect actor executor assumption` → root cause #1 (fixed)
- termination "background task ... expired" / RunningBoard → linger fix (fixed)
- `0x8badf00d` with `didReceiveRemoteNotification` frames → backlog #1
- `0xdead10cc` → backlog #3 · jetsam, no stack → backlog #4
