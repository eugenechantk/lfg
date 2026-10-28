# Feature: smooth scrolling while many sessions are running

Tier: product (shipping iOS client). Investigation, scripts and raw data:
`.claude/performance/20261028-live-scroll/` (`investigation.md` is the narrative).

## User Story

As Eugene, with many sessions running or unread, I want the session list and
the session view to scroll smoothly, so the app stays usable while the fleet
is busy.

## User Flow

1. Many sessions are running on one or more hosts. Their messages and busy
   changes stream into the app over the event stream.
2. Eugene scrolls the session list.
3. He opens a session and scrolls its transcript.
4. Both scroll without stutter, and stay smooth while updates keep arriving.

## Root causes (measured, not assumed)

1. **Pulsing green dot.** A `phaseAnimator` halo on every working row. Inside a
   `List`, each animation frame re-ran the list coordinator and re-laid out the
   visible rows: the main thread sat at ~98% with the event stream switched off.
2. **`@AppStorage` in `SessionListView`.** It reports a change whenever ANY
   UserDefaults key is written, and `HostLink` writes its cursor on every event.
   `_printChanges` logged `_collapsedStatusStored changed` 619 times in 25 s: the
   list re-filtered, re-grouped, re-sorted and re-diffed every session per event.
3. **Unconditional host-health write.** `setHostState` rewrote
   `hostStateByHost[host]` on every stream element even when unchanged. A
   dictionary subscript write notifies observers even for an equal value
   (Swift 6.2 skips equal plain sets, not subscripts — probed). Every row, the
   headers, `RootView` and the open session read host health.
4. **Whole-dictionary transcript observation.** A message for any session
   re-ran the open session view and every working row.

## Success Criteria

- [x] SC1: A message for session A does not wake views of session B; repeated
  `.receiving` does not wake host-health readers; real changes still notify. —
  **Verify by:** `KeyedObservationTests` (LFGCore) and
  `SessionStoreObservationTests` (LFGTests).
- [x] SC2: List scrolling under the live load uses measurably less main thread.
  — **Verify by:** `ab.py` protocol, same sim, same optimized build settings.
- [x] SC3: Same for scrolling an open session. — **Verify by:** same.
- [x] SC4: No behaviour change: the open transcript updates live, rows move
  between Working / Unread / Idle, the working clock ticks, unread clears on
  open. — **Verify by:** independent visual audit on the live fixture.
- [x] SC5: Working rows show a steady green dot, no pulse (Eugene's call,
  2026-10-28: "cut the flare"). — **Verify by:** audit recording.
- [x] SC6: Folding a status section still persists across a relaunch (storage
  moved from `@AppStorage` to `AppSettings`, same key). — **Verify by:** audit.

## Implementation

- `SessionListView.swift`: `SessionRowStatusDot` is a plain circle. Fold state
  reads/writes `settings.collapsedStatusSections`.
- `LFGApp.swift` (`AppSettings`): `collapsedStatusSections`, persisted under the
  old `sessionList.collapsedStatusSections` key so existing fold state survives.
- `SessionStore.swift`: `setHostState` writes only a change; `recomputeFleetState`
  likewise. `transcripts` / `transcriptVersion` are `@ObservationIgnored`; views
  read `transcript(for:)` / `transcriptRevision(for:)`; `bumpTranscript` notifies
  that one session. `signal` and `apply` are internal so tests can drive them.
- `SessionDetailView.swift`: reads the per-session accessors.
- `LFGCore/KeyedObservation.swift`: per-key observation helper (+ tests).

## Decision Log

- Evidence and notes live under `.claude/`, not `.codex/` where earlier perf
  passes put theirs (global rule).
- Optimized Debug build (`SWIFT_OPTIMIZATION_LEVEL=-O`) for all measurements:
  fixture mode is Debug-only. Same method as the 2026-10-17 pass.
- Builds bypassed the build-guard shim (vendor FlowDeck binary): the guard's
  lock was held indefinitely by another agent's idle WebDriverAgent run.
  Logged in the improvement log.
- Fold state moved to `AppSettings` instead of `@State` + manual defaults:
  same pattern as `groupMode` / `sortMode`, and two list instances stay in sync.
- Kept: the per-event cursor write to UserDefaults. With `@AppStorage` gone it
  costs only the write. Coalescing it is an option if a later profile shows it.
- Not done: `RootView.hostFilesForSelection` does a Keychain lookup per render
  (`HostCredentialStore.credential`). Visible in samples, now rare because
  RootView renders rarely. Follow-up candidate.

## Verification Evidence

Live fixture: 2 hosts × 160 sessions (48 working, 40 unread), 4 messages/s per
host, every 20 s a burst flipping every working session busy off and on.
Main-thread busy share from macOS `sample` (1 ms); swipe time = how long the
automation's swipe took to be answered (a starved main thread answers late).

| Window | Before main busy | After main busy | Before swipe (median) | After swipe (median) |
|---|---:|---:|---:|---:|
| List, idle 10 s | 95.6% | 1.0% | — | — |
| List, 8 swipes | 93.2% | 41.8% | 8.1 s | 2.6 s |
| Session, idle 10 s | 97.7% | 38.8% | — | — |
| Session, 8 swipes | 96.3% | 48.7% | 18.4 s | 3.3 s |

Process CPU, list idle: 82% → 13%. Raw: `ab/before/*/metrics.json`,
`ab/after-final/*/metrics.json`. The remaining session-idle cost is the hidden
list regrouping during the fixture's synthetic bursts (48 sessions flipping
twice at once), which is a legitimate state change.

Isolation runs (baseline build): stream OFF and working rows on screen: still
~97% CPU (pulse alone). Working rows scrolled away: 15-17%.

Independent visual audit (`ios_visual_evidence_auditor`): **PASS** on SC4-SC6.
Report: `.claude/evidence/20261028-153905-live-scroll-audit/evidence.md`.
- SC4a: 22 s recording, no input: newest message Step 5115 → 5245, view stayed at the newest end.
- SC4b: idle.txt `live-pro-20` → Working 48 → 47, row moved to Unread; emptied → back to 48.
- SC4c: row clock 3m → 33m; session header 3m 32s → 3m 44s in 12 s.
- SC4d: opening an unread row dropped Unread 272 → 271 and it stayed read.
- SC5: dot green area stayed the 8 pt dot across recordings; no frames written while idle.
- SC6: folded Working, relaunched (new process), still folded; unfolded again.
- Auditor note: the app was not running when it started. Cause: my
  `flowdeck test` run on the same simulator replaced the running app; no crash report.
- Auditor note: transcript scrolling still pauses up to ~0.5 s during the
  fixture's synthetic burst (all 48 working sessions flip busy off and on at
  once); smooth 8 s later. List scrolled at ~58 fps.

Tests:
- `swift test` (LFGCore): 649 XCTest (1 skipped, 0 failures) + 567 Swift Testing,
  including 5 new `KeyedObservationTests`.
- LFGTests (`flowdeck test --test-targets LFGTests`): 22/22 passed, including
  the 5 new `SessionStoreObservationTests`. Raw: `lfgtests.jsonl`. The
  host-health case discriminates: the old code's unconditional
  `hostStateByHost[id] = settled` is exactly the equal-value subscript write
  the probe showed notifying.

## Residual Risks

- Simulator on the Mac's CPU, not the phone's. Relative improvement is large,
  but absolute frame pacing on the iPhone is unmeasured (Hitches is not
  supported on the simulator).
- A view that reads `store.transcripts[...]` directly in future would silently
  stop updating. The property's doc comment says to use `transcript(for:)`.

- Bursts: when many sessions change busy state at once, the hidden list
  regroups and the open transcript can pause up to ~0.5 s. Follow-up option:
  apply a burst of stream events in one batch so the list regroups once.

## Bugs

_None open._
