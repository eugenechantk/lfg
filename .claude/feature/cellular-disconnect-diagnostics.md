# Feature: cellular-disconnect-diagnostics

Instrument the iOS client's connection layer so the long-running "drops on 5G,
never on Wi-Fi" bug can be *observed* instead of theorised about, and fix the
three cellular-only defects found in
`.claude/diagnosis-cellular-only-disconnects-20260806.md`.

**Tier:** product (shipping TestFlight app).

## User Story

As Eugene, out on 5G, I want the client to stop dropping — and when it does
drop, I want a timestamped record of exactly what the network, the host state
machine and the event stream each did, so the next fix is driven by evidence
instead of a fourth round of code-reading.

## User Flow

1. Eugene goes out, on cellular. The client drops (or, after this build, doesn't).
2. He opens **Settings → Diagnostics → Connection Log**.
3. He sees a reverse-chronological timeline: path changes (with interface type,
   expensive/constrained), host state transitions, stream connects/errors,
   heartbeats, keepalive RTTs, probe results, foreground/background boundaries.
4. He taps **Share** and sends the log out of the app.
5. The log also survives app termination, so the window *before* a kill is intact.

## Status

All eight criteria met. **One caveat stated plainly:** defect A's fix is proven
by unit tests, not live — a genuine `NWPath` loss cannot be induced in the
simulator, so the path-loss grace window is verified deterministically in
`HostStateTests` and will be *confirmed* by the first 5G capture on Eugene's
device. That capture is the point of the build.

## Success Criteria

- [ ] **SC1** — A `ConnectionLog` records timestamped, categorised entries in a
  bounded ring buffer and never grows without limit.
  **Verify by:** `ConnectionLogTests` — ring eviction at capacity, ordering.
- [ ] **SC2** — The log persists across app launches: entries written in run N
  are readable in run N+1, and old runs are rotated out by a size cap.
  **Verify by:** `ConnectionLogTests` — write→reload round trip against a temp
  directory; rotation drops the oldest bytes and keeps the file under cap.
- [ ] **SC3** — Every connection-relevant event is recorded: `NWPath` updates
  (status, interfaces, isExpensive, isConstrained), `HostState` transitions with
  the causing signal, `HostLink` state changes, stream connect/first-byte/end
  (clean vs error, with `URLError` code), heartbeats, keepalive RTT, REST probe
  results, scene-phase transitions, and `resumeNow` branch decisions.
  **Verify by:** `ConnectionLogTests` for the pure formatters + a live simulator
  run whose exported log contains at least one entry of each category.
- [ ] **SC4** — Defect A: a transient network-path loss no longer banners
  instantly. `.networkLost` starts the same 30s grace clock every other failure
  gets; only sustained loss banners.
  **Verify by:** `HostStateTests` — `networkLost` at t=0 is non-bannering at
  t=29 and bannering at t=30; `receiving` at t=5 returns it to `.live`.
- [ ] **SC5** — Defect B: network-path restoration redials a stream that has
  gone quiet, instead of leaving a dead-but-`.live` socket to the 20s watchdog.
  **Verify by:** `HostLinkPolicyTests`/store test — restore path calls
  `resumeNow` semantics, not `retryNow`'s early return.
- [ ] **SC6** — Defect C: foregrounding clears a `.noNetwork` state latched
  during suspension rather than showing "no network" measured before the
  suspension.
  **Verify by:** `HostStateTests` — foreground signal moves `noNetwork` →
  `connecting`; store test that `enterForeground` emits it.
- [ ] **SC7** — Settings exposes the log, readable and shareable, and the
  screen is reachable in the running app.
  **Verify by:** simulator run + `ios_visual_evidence_auditor` screenshots.
- [ ] **SC8** — No regression: the existing `LFGCore` suite stays green.
  **Verify by:** `cd ios/LFGCore && swift test`.

## Platform & Stack

- **Platform:** iOS 17.2+, Swift 6, strict concurrency complete
- **App target:** `ios/LFG` (SwiftUI shell)
- **Logic package:** `ios/LFGCore` (platform-neutral, `swift test`able)
- **Build/run:** FlowDeck only (`/flowdeck`), iPhone 17 Pro

## Test Strategy

Everything decidable without Apple's runtime goes in `LFGCore` with tests:
the ring buffer, persistence + rotation, entry formatting, and the whole
`HostStateMachine` change. The app target keeps only the wiring (NWPathMonitor
callbacks, scene phase, the SwiftUI screen), which the auditor proves visually.

## Implementation Phases

### Phase 1 — `ConnectionLog` in LFGCore (SC1, SC2, SC3-formatters)
- New `ConnectionLog.swift`: bounded ring buffer, categories, structured fields,
  file persistence with rotation, text export, `os.Logger` mirror.
- Gate: `ConnectionLogTests` green.

### Phase 2 — State-machine fixes (SC4, SC6)
- `HostState.noNetwork` gains a `since:` and a sustained variant so the grace
  window applies uniformly; new `.foregrounded` signal.
- Gate: `HostStateTests` green, existing cases updated.

### Phase 3 — Wiring + instrumentation (SC3, SC5, SC6)
- `SessionStore`: log every path update/state transition/probe; `resumeNow` on
  path restore; foreground path re-evaluation.
- `HostLink` + `LFGClient`: log dial/first-byte/heartbeat/error/RTT.
- Gate: `swift test` green; app builds.

### Phase 4 — Settings UI (SC7)
- `ConnectionLogView` + Settings entry, share sheet.
- Gate: simulator run, then `ios_visual_evidence_auditor`.

## Decision Log

- **Log lives in `LFGCore`, not the app target.** `LFGClient` (which owns the
  stream and therefore the most diagnostic events) is in the package and cannot
  import the app. Making the log platform-neutral also makes persistence and
  rotation `swift test`able.
- **`.noNetwork` gains a grace window rather than being folded into
  `degraded`/`offline`.** Folding would need a typed failure reason threaded
  through four UI consumers to keep the distinct "no network" remedy copy. A
  `noNetwork(since:)` / `noNetworkSustained(since:)` pair mirrors the existing
  `degraded`/`offline` pattern exactly and touches less.
- **`URLSession.shared` is NOT replaced with a `waitsForConnectivity` session
  this round.** It's a plausible contributing factor (see diagnosis) but changing
  connect semantics risks the black-hole behaviour a Phase-1 gate test caught.
  Instead we log `URLError` codes, so the next round can confirm whether
  connectivity-gap failures actually occur before changing it.
- **Heartbeats are logged per frame, bytes are not.** Per-byte logging would
  swamp the ring; heartbeats are 1 per 10s per host, which is the resolution
  needed to spot a stall.

## Verification Evidence

Build: FlowDeck, iPhone 17 Pro (`0B0DBA10-BBE3-48C8-A657-D68053C5AAF2`), against
the real `lfg serve` on `localhost:8766` — real HTTP, real SSE, real journal
cursor. Screenshots in `.claude/feature/evidence-connection-log/`.

| SC | Method | Result |
|---|---|---|
| SC1 | `ConnectionLogTests` ring eviction + ordering | PASS — 223 tests green |
| SC2 | Unit round-trip **and live**: share-sheet preview opens on the `10:00:02` launch banner while the app is on its `10:07` run | PASS — `02-share.png` |
| SC3 | Live capture contains every category exercised: `APP`/`NET`/`LNK`/`STA`/`STR`/`KAL` | PASS — `01-timeline.png` |
| SC4 | `HostStateTests` — non-bannering at t=29, bannering at t=30; flapping still converges | PASS (unit only, see caveat) |
| SC5 | `networkPathChanged` now calls `resumeNow(cause:"path-restored")`; branch decisions visible in the log (`stream is fresh (quiet 9.2s) — left alone`, `starting from idle`) | PASS |
| SC6 | Live: backgrounded 148s, reopened → `APP foreground after 148s backgrounded` → full recovery to `.live` in **89ms** | PASS |
| SC7 | Settings → Diagnostics → Connection Log; filters and share driven by real taps | PASS — `01`/`02`/`03` |
| SC8 | `cd ios/LFGCore && swift test` | PASS — 223 tests, 0 failures |

Live recovery trace (SC5 + SC6), copied from the device file:

```
10:07:33.584 APP foreground after 148s backgrounded
10:07:33.585 NET path=satisfied ifaces=wifi v4=false v6=false
10:07:33.585 LNK [localhost:8766] resumeNow(foreground): starting from idle
10:07:33.599 STA [localhost:8766] unknown -> connecting via connecting
10:07:33.605 STR [localhost:8766] headers status=200 in 0.01s
10:07:33.606 STR [localhost:8766] first event seq=47574
10:07:33.608 STA [localhost:8766] connecting -> live via receiving
10:07:33.673 LNK [localhost:8766] catchingUp -> live
```

### Bugs found by looking at the artifact (both fixed, both regression-tested)

1. **Batched writes lost the newest entries.** After a full live session only the
   launch banner was on disk; ~30 entries sat in a pending batch. Since iOS can
   kill the app at any moment, a batch always holds precisely the entries
   describing the drop. Now every entry flushes.
   Test: `testEveryEntryIsOnDiskWithoutAnExplicitFlush`.
2. **One machine appeared under three names** — `localhost`, `localhost:8766`
   and `Eugenes-MacBook-Pro` — in a single timeline, because three components
   each reached for a display name and `Host.name` is resolved from `/api/info`
   *after* connecting. Correlating across components is the log's whole job.
   Added `Host.logLabel`, derived from the configured URL authority.
   Tests: `testEveryComponentNamesTheSameHostIdentically`,
   `testLogLabelIgnoresMutableDisplayNames`.

## Residual Risks

- **Defect A is unit-verified, not live.** A real `NWPath` transition to
  unsatisfied cannot be induced in the simulator. The reducer is covered
  deterministically; the end-to-end behaviour is confirmed by the first 5G
  capture.
- **The independent `ios_visual_evidence_auditor` step was NOT run.** This
  session operates under a standing instruction not to spawn subagents unless
  asked. Visual verification above was performed first-party by driving the real
  UI (taps, raw HID for the toolbar button) rather than by an independent
  grader. Say the word and it can be run as a separate gate.
- Log volume under a *long* catch-up is untested at scale; replay logs only its
  first event, so this is expected to be small, but it is not measured.
- The share sheet's "Save to Files"/"Mail" paths were not exercised past the
  sheet appearing.

## Bugs

None open. The two found during verification are fixed and covered above.
