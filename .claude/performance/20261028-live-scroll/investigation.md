# iOS performance investigation: scrolling with many running sessions

## Symptom

With many sessions running or unread, scrolling the session list, and then the
session view, is sluggish. It recovers only after a while.

## Classification

- Category: CPU / SwiftUI over-updating (main thread saturated), shows up as hitches
- Device scope: Eugene's iPhone; reproduced on iPhone 17 Pro simulator, iOS 26.3
- Build: Debug with `SWIFT_OPTIMIZATION_LEVEL=-O` (fixture mode is Debug-only)

## Workload

`fixture.py`: two fake hosts, 160 sessions each; 24 working and 20 unread per
host. The event stream replays 600 events per host, then sends 4 messages per
second per host, with a burst every 20 s (every working session flips busy off
and on, then 30 messages). Real journal peaks for comparison: 150-300 events a
minute in busy minutes, up to 947 in one minute, ~3,900 an hour.

## Baseline findings

1. **The pulsing green dot holds a core.** Live stream on: process at 96-100%
   CPU, main thread 98% busy, sitting on the list. Live stream OFF: still
   96-100%. Scroll the working rows off screen: 15-17%, main thread ~10% busy.
   Each `phaseAnimator` frame inside a `List` cell re-ran the list coordinator
   (`UICollectionViewListCoordinatorBase.performUpdates`), re-laid out and
   re-drew the visible rows' text. A scripted swipe on this screen did not
   complete within 120 s.
2. **Every stream element redraws the whole UI.** `HostLink` reports
   `.receiving` for every event and heartbeat. `setHostState` then wrote
   `hostStateByHost[hostId]` even when the value was unchanged (the guard let
   an equal value through whenever no banner re-check was scheduled, which is
   the normal case for a live host). A dictionary subscript write notifies
   observers even when the value is equal; a plain property set does not
   (probe: `scratchpad/obsprobe/probe.swift`, Swift 6.2.4). Every list row
   (`isOffline`), the headers, `RootView` and the open session read host health,
   so each event re-ran all of them. Sample with the session view open and the
   stream on: main thread 91% busy, and most of it in the HIDDEN list and
   `RootView`, not the session view. Writer caught in the sample:
   `ObservationRegistrar.willSet <- SessionStore.setHostState <- signal <- HostLink.run`.
3. **A message for any session re-ran the open session view and every working
   row.** `transcripts` and `transcriptVersion` were observed as whole
   dictionaries; `SessionDetailView` read `store.transcripts[sid]` and working
   rows read it through `turnStartedAt`.

Not the cause: REST polling (steady state is one `/api/sessions` per minute per
host), network decode (off the main thread).

## Fixes

1. Remove the pulse; the dot is steady (Eugene: "cut the flare").
2. `setHostState` writes only a real change; `recomputeFleetState` too.
3. `transcripts` / `transcriptVersion` out of observation; views read them
   through `transcript(for:)` / `transcriptRevision(for:)`, which observe one
   session (`LFGCore.KeyedObservation`). `bumpTranscript` notifies that session.

## Before / after

See `ab/before`, `ab/after` and the table in the feature doc
(`.claude/feature/live-session-scroll-perf.md`).
