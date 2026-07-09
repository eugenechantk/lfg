# Feature: multihost-fanout-resilience

Tier: **product** (shipping TestFlight app) → full `/ios-development` workflow.

## User Story

As someone running lfg agents across two machines, when one host is offline (asleep,
closed lid, off the tailnet), the iOS client should stay as responsive as if that host
were never configured. Today a single offline host makes the whole app feel broken:
foregrounding stalls ~15s before live updates resume, and tapping a push notification
stalls ~15s before the session opens.

## Root cause

Confirmed empirically on 2026-07-09 (see `.claude/diagnosis-macbook-air-flakey-connection.md`):

- An offline Tailscale peer is a **black hole** — packets are dropped, no RST, no
  connection refused. `curl` to `100.120.101.14:8766` (`macbook-pro-2`, offline):
  `http=000 connect=0.000000 total=15.004652`. It hangs for the full timeout.
- `SessionStore.fetchSessionsAllHosts()` fans out in a `withTaskGroup` and then does
  `for await r in group { out.append(r) }` — **a barrier**. It waits for the slowest host.
- `LFGClient.get()` uses `timeoutInterval = 15`.
- `ensureStream()` — which re-establishes the per-host SSE streams — is the **last line
  of `refresh()`**, so SSE reconnect is gated behind that 15s barrier.
- `RootView.swift:90` calls `await store.refresh()` on `scenePhase == .active`, and
  `resolveDeepLink` (`SessionStore.swift:217`) awaits `refresh()` before resolving a
  notification tap.

Net effect: 3s poll loop is really an ~18s loop; every foreground and every notification
tap eats a hard 15s stall.

Two aggravators found while tracing:

- **No guard against concurrent `refresh()`.** The scenePhase handler fires one while the
  poll loop's own is in flight → two 15s refreshes racing to assign `sessions`.
- **`ensureStream()` opens streams against unreachable hosts.** The SSE watchdog
  (`streamStaleTimeout = 35`) eventually kills them, but it wastes a task and 35s per cycle.

This is independent of, and compounds with, a Surfshark VPN route conflict on the host
(same diagnosis doc). The fan-out barrier is the dominant user-visible symptom.

## User Flow

1. Two hosts configured; `macbook-pro-2` is offline.
2. User backgrounds the app, then foregrounds it (or taps a push notification).
3. The reachable host's sessions and live SSE stream come up **immediately** (~100ms).
4. The offline host is marked unreachable and quietly backs off; its cached sessions stay
   listed and dimmed (existing `MultiHost.isOffline` behaviour, unchanged).
5. When the offline host returns, it is picked up within one cold-probe interval (~30s).

## Success Criteria

- **SC1** — A refresh applies each host's result **as it arrives**; one host being slow or
  dead cannot delay another host's sessions appearing.
- **SC2** — `ensureStream()` runs for a healthy host as soon as that host's fetch lands,
  not after the slowest host. SSE reconnect on foreground is not gated on a dead host.
- **SC3** — The poll path uses a short per-host timeout (4s), not the 15s user-initiated
  timeout, so a worst-case poll cannot exceed ~4s.
- **SC4** — A host that has failed `>= failureThreshold` consecutive times is "cold" and is
  probed only every Nth poll tick, not every tick. It recovers on the next probe that succeeds.
- **SC5** — Concurrent `refresh()` calls coalesce onto the in-flight one; `sessions` is never
  assigned by two racing refreshes.
- **SC6** — `ensureStream()` does not open streams against hosts currently marked unreachable,
  and re-establishes them when the host recovers.
- **SC7** — Aggregate `reachability` is derived from the persisted per-host health map, not
  from the set of hosts probed on this tick (a cold-skipped host must not read as "no host
  configured").
- **SC8** — Existing multi-host merge/route/offline semantics are unchanged (regression).

## Test Strategy

The new decision logic is pure and goes in `LFGCore` so `swift test` proves it without a
simulator. The `SessionStore` wiring is the thin shell.

- SC4, SC7 → `HostHealth` pure policy functions (new `LFGCore/HostHealth.swift`).
- SC1, SC2, SC5, SC6 → `SessionStore` structural change; verified by the incremental-merge
  unit tests where the logic is pure, and by **live simulator verification against a real
  offline host** for the async/ordering behaviour that Swift Testing cannot prove.
- SC3 → `LFGClient.sessions(timeout:)` surface + call-site assertion.
- SC8 → existing `MultiHostTests.swift` must stay green.

Residual risk is called out below: the ordering guarantee (SC1/SC2) is an async property of
`withTaskGroup`; unit tests can prove the merge is incremental, but only a live run against a
black-holed host proves the stall is gone. That live run is **required**, not optional — per
`verify-real-seam-not-mocks`.

## Tests

### Package Unit (`cd ios/LFGCore && swift test`) — 73/73 passing

- `LFGCore/Tests/LFGCoreTests/HostHealthTests.swift` (15 cases, new)
  - `testHealthyHostIsProbedEveryTick`, `testFailuresBelowThresholdStillProbedEveryTick`,
    `testAtFailureThresholdGoesCold`, `testColdHostProbedOnlyOnEveryNthTick`,
    `testColdBackoffRespectsCustomInterval`, `testZeroProbeIntervalDegradesToEveryTickAndNeverDividesByZero`,
    `testRecoveredHostIsProbedOnTheVeryNextTick` — verify **SC4**
  - `testPollTimeoutIsFarBelowUserInitiatedTimeout` — verifies **SC3**
  - `testNoConfiguredHostsAggregatesToNoHostConfigured`, `testAnyHealthyHostMakesAggregateOK`,
    `testAllDownSurfacesFirstConfiguredHostsFailure`,
    `testColdSkippedHostKeepsRememberedStateAndNeverReadsAsUnconfigured`,
    `testConfiguredButNothingProbedYetIsUnknownNotFailure`,
    `testHealthEntriesForRemovedHostsAreIgnored` — verify **SC7**
  - `testColdThresholdExceedsTheVisibleOfflineDebounceThreshold` — pins the coupling
    between `HostProbePolicy.failureThreshold` (4) and `SessionStore.failureThreshold` (3).
- `LFGCore/Tests/LFGCoreTests/MultiHostTests.swift` (unchanged) — **SC8** regression, still green.

### Live real-seam verification (SC1, SC2, SC3, SC4, SC6)

Swift Testing cannot prove an async ordering property. Per `verify-real-seam-not-mocks`, this
was measured against a **genuinely black-holed host** — `macbook-pro-2` (`100.120.101.14:8766`),
a real offline Tailscale peer — with the live Air (`100.75.162.40:8766`) as the healthy host.
Two-host config written straight into the simulator's prefs plist (the `ios/CLAUDE.md` trap
about URL text fields).

Harness: `.claude/feature/multihost-fanout-evidence/sse_probe.py` samples `lsof` every 200ms.
The simulator app appears as its own process, so connections are attributable; the SSE stream
is the connection to the healthy host that *persists* (short ones are the 3s REST polls).

Evidence: `probe-healthy-host-first.txt`, `probe-dead-host-first.txt`.

**With the dead host listed FIRST** (harshest ordering — head-of-line blocking + order-sensitive
`mergeSessions` first-wins and `HostHealth.aggregate` first-configured):

```
[+ 0.00s] NEW  100.120.101.14:8766      SYN_SENT      <- dead host: no RST, black hole
[+ 0.00s] NEW  100.75.162.40:8766       ESTABLISHED   <- healthy host's SSE stream, ALREADY UP

remote                      first_seen   lifetime  states
100.120.101.14:8766             +0.00s     15.12s  SYN_SENT       (one-shot info(), 15s default)
100.75.162.40:8766              +0.00s     91.70s  ESTABLISHED    (SSE stream — whole window)
100.120.101.14:8766             +0.28s      3.58s  SYN_SENT       (poll — 4s budget)
100.120.101.14:8766             +8.28s      3.57s  SYN_SENT
100.120.101.14:8766            +15.40s      3.63s  SYN_SENT
100.120.101.14:8766            +22.35s      3.66s  SYN_SENT
100.120.101.14:8766            +45.62s      3.90s  SYN_SENT
100.120.101.14:8766            +82.53s      3.61s  SYN_SENT
```

Readings:

- **SC1 + SC2** — at the very first sample the healthy host's stream is `ESTABLISHED` while the
  dead host is still `SYN_SENT`. Under the old code `ensureStream()` was the last statement
  after an awaited barrier, so it *could not* have run before the dead host's request finished.
  The stream then persists 91.70s, unbroken, across every dead-host failure.
- **SC3** — every poll-path connection to the dead host dies at **3.57–3.90s**, the 4s
  `pollTimeout`. Pre-fix these were 15s (measured: `curl … total=15.004652`).
- **SC4** — probe gaps to the dead host: `0.28 → 8.28 → 15.40 → 22.35 → 45.62 → 82.53`.
  Deltas `7.1s, 7.1s, 7.0s` (a failed 4s probe + 3s sleep, every tick) up to 4 consecutive
  failures, then `23.3s, 36.9s` — the cold back-off engaging exactly as specified.
- **SC6** — no stream is ever opened against the dead host; its only connections are the
  short poll probes and the one-shot identity call.

`probe-healthy-host-first.txt` shows the same behaviour with the ordering reversed.

## Implementation Details

- **`LFGCore/HostHealth.swift`** (new) — `HostProbePolicy` + pure `isCold` / `shouldProbe` /
  `aggregate`. All decision logic, no networking, fully unit-tested.
- **`LFGCore/LFGClient.swift`** — `get`, `sessions`, `resumable` take a `timeout:` defaulting to
  the new `LFGClient.readTimeout` (15s). Purely additive; existing callers unchanged.
- **`LFG/SessionStore.swift`**
  - `fetchSessionsAllHosts` → `fetchSessionsStreaming(_:timeout:onResult:)`. The barrier
    (`for await r in group { out.append(r) }` then apply) becomes `for await f in group { onResult(f) }`,
    applying each host's result as it lands.
  - `refresh()` is now a coalescing wrapper over `performRefresh()` (**SC5**); concurrent callers
    join the in-flight run instead of racing to assign `sessions`.
  - Extracted `applyHostFetch(_:)` and `rebuildSessions()` so the merge is cheap + idempotent and
    can run once per arriving host.
  - `performRefresh` skips cold hosts via `HostHealth.shouldProbe`, and derives the aggregate
    banner from the persisted `reachabilityByHost` via `HostHealth.aggregate` (**SC7**).
  - `ensureStream()` refuses to open a stream against a host not currently `.ok`, tearing down
    and clearing its id key so it re-establishes on recovery (**SC6**).
  - `reconcilePendingViaQueue()` skips sessions whose owning host is down — it is a sequential
    loop, so one black-holed owner would stall every session behind it.
  - `resolveHostIdentities()` was a **sequential** loop of 15s `info()` calls — the same
    head-of-line bug at launch (a dead host listed first delayed every healthy host's chip label
    by 15s). Now fans out concurrently. *Found by reading the probe output, not by inspection.*
  - `stop()` also cancels the in-flight refresh; `reconnect()` resets `pollTick`/`liveIds`.
- **`LFG/RootView.swift`** — `scenePhase` gains a `.background` branch (`store.stop()`) and
  `.active` now calls `store.start()` before refreshing. `.inactive` deliberately does nothing
  (it fires for the app switcher, Control Center and incoming calls, where streams are still good).

## Residual Risks

- **No visual/UI proof captured.** `flowdeck ui simulator screen --screenshot` crashes with an
  `NSException` because `xcode-select -p` points at `/Library/Developer/CommandLineTools`;
  `DEVELOPER_DIR` does not help `idb` (memory `flowdeck-ui-needs-real-xcode-select`). Fixing it
  needs `sudo xcode-select -s /Applications/Xcode.app`. The change has **no visual delta** — it is
  a latency/ordering fix — and the network-level evidence above measures the property directly,
  so this is a documented gap rather than an unverified criterion.
- **`resolveHostIdentities()` still uses the 15s timeout** against a dead host (visible as the
  `15.12s` SYN_SENT above). It no longer blocks anything, but it is a wasted 15s socket at launch
  and appears to run more than once while a name stays unresolved. Follow-up, not a regression.
- **`loadCreateMetadata()`** was not audited for the same head-of-line pattern.
- The cold-probe interval (~30s) is a guess. It trades recovery latency for cost; if a host
  returning from sleep feels slow to reappear, lower `coldProbeEveryNTicks`.
- The `HostProbePolicy.failureThreshold` (4) / `SessionStore.failureThreshold` (3) coupling is
  enforced only by a test asserting the inequality, not by construction.

## Bugs

- Fixed in this change: `resolveHostIdentities()` head-of-line blocking (see above).
- **Pre-existing, unrelated, still open:** a Surfshark VPN on the host captures the default route
  and breaks Tailscale NAT traversal. See `.claude/diagnosis-macbook-air-flakey-connection.md`.
  That degrades path *quality*; this change fixes the hard stalls. They compound.
