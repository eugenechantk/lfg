# Delegation Brief: fix live transcript stall for app-created sessions (iOS)

## Goal

A session created from inside the iOS app must show its live messages in the transcript
view that is already open. Today it shows only the optimistic bubble and never updates
until you navigate away and back (or relaunch the app).

## Reproduction (observed on a simulator against a live server, 2026-07-31)

1. In the app: `+` → agent "Codex (CLI)" → type a prompt → send.
2. The app navigates into the new session's detail view and shows the optimistic user bubble.
3. The agent replies; four more messages are exchanged over the next several minutes.
4. **The open detail view never shows any of them.** It stays at the single bubble.
5. Navigate back to the list and tap the same session → all messages appear immediately.
6. Relaunch the app, open the same session, send another message from outside → the new
   message and its reply appear live, with the view open, no navigation. Live streaming
   works perfectly for a session that was NOT created in this app run.

Server side is NOT at fault — verified independently: `/api/events?since=<cursor>` delivers
all `msg` frames for that session correctly while the stall is happening.

## Where to look

`ios/LFG/SessionStore.swift`.

Creation is optimistic: `send`/create makes a `placeholder` id, appends an optimistic
session, then `attemptCreate` (~line 2247) POSTs `/api/sessions/new`. **That POST now takes
10–14 seconds for codex** (the server waits for the agent to write its transcript). On
success it calls `remap(from: placeholder, to: realId)` (line 2275), `requestSelection(realId)`,
then `refresh()`.

Meanwhile the host-wide SSE link is already delivering `msg` events keyed by the REAL id —
they can and do arrive DURING those 10–14 seconds, before the client knows that id exists.
`applyIngested` (line 924) notices `session(sid) == nil` and schedules a throttled refresh,
but `apply(event)` (line 1615) still appends them to `transcripts[realId]` and records their
keys in `seen[realId]`.

### Candidate defect A — `remap` clobbers instead of merging

```swift
if let v = transcripts.removeValue(forKey: old) { transcripts[new] = v }
...
if let v = seen.removeValue(forKey: old) { seen[new] = v }
```

Every one of these is an **overwrite** of the destination key. If live events for `realId`
already populated `transcripts[realId]` / `seen[realId]`, the remap discards them and replaces
them with the placeholder's contents. SSE never replays, so those messages are gone from the
in-memory transcript until a REST reload.

### Candidate defect B — the open detail view doesn't follow the id swap

`requestSelection(new)` sets `requestedSelection`, which `RootView.swift:84` copies into
`selection` (the NavigationSplitView selection). Verify this actually re-binds the pushed
detail view to the new id on a compact/iPhone layout. If the detail view keeps rendering the
placeholder id, it reads `transcripts[placeholder]` — which `remap` just emptied — which
matches the observed "only the optimistic bubble, forever."

### Also check — `hostBySession` is never remapped

`attemptCreate`'s caller sets `hostBySession[placeholder] = host.id` (~line 2237). `remap` does
not move it to the new id, so per-session host routing for the new id falls back to whatever
`client(forSession:)` defaults to. Fix if it is a real defect; say so if it is not.

## Spec

**Diagnose first, then fix.** A and B are candidates, not conclusions — determine which one(s)
actually produce the observed behavior and say so explicitly in your report. Do not blindly
patch both and declare victory; if only one is real, fix that one and explain why the other
is not.

Required behavior:

- Messages that arrived for the real id **before** the create response must survive the remap
  and appear in the open transcript. Merge, don't overwrite — union the two message lists,
  de-duplicated by the same `stableID` key `apply` uses, in timestamp/arrival order, with no
  duplicate bubbles.
- Messages that arrive **after** the remap must appear live in the already-open view.
- The optimistic bubble must still reconcile exactly as it does today — no double-rendering of
  the kickoff message once the real user turn lands (`reconcilePending`).
- No regression to the resumed-session path, which also calls `remap` (`resumedIds`, the
  `closed = false` revival, and the "no session selected flash" behavior the comments describe).

## Constraints

- Only touch files under `ios/`. Do NOT touch `src/`, `web/`, or any server code — the server
  side is verified correct and has separate uncommitted fixes in flight.
- Do not restart the lfg server or any tmux session.
- Match the file's existing comment style: these are subtle concurrency/ordering behaviors and
  the codebase documents the "why" above such code. A merge that silently replaces an
  overwrite needs a comment saying what race it is defending against.

## Verification

1. `swift test` in `ios/LFGCore` must stay green (141 tests currently pass).
2. Build the app: `flowdeck build` from `ios/` (do not run/launch it — a simulator session is
   already in use by Claude).
3. **Add a regression test.** If the remap/merge logic is not reachable from the existing
   `LFGCoreTests` target, extract the merge into a small pure function that is testable and
   test it there (message-union-by-stableID, order, no duplicates). If you genuinely cannot
   make it testable without a disproportionate refactor, say so explicitly rather than
   shipping an untested behavioral fix — do not invent a test that doesn't exercise the path.

Claude will re-run the full simulator repro (create a codex session from the app UI and watch
the open view) to confirm the fix.

## Definition of done

- [ ] Root cause identified and stated (A, B, both, or something else)
- [ ] Pre-remap messages survive; post-remap messages appear live
- [ ] Optimistic bubble reconciliation and the resume path unregressed
- [ ] `swift test` green; `flowdeck build` succeeds
- [ ] Regression test added, or a clear written explanation of why it could not be

## Report back

Root cause, files changed, verification output, whether `hostBySession` was a real defect, and
anything you left incomplete.
