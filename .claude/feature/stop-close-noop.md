# Feature: stop-close-noop

Fixes the defects diagnosed in `.claude/diagnosis-stop-close-noop-20260806.md`.

## User Story

As someone driving many agent sessions from the iOS client, I want **Stop** and **End session**
to actually stop and end the session — and, when they can't, to say so — so that I am not left
tapping a button that reports success and does nothing.

## User Flow

1. A session wedges (upstream 403 after a `/login` expiry) mid-turn.
2. The list shows it as **Paused / not signed in**, not "running".
3. If a session really is mid-turn, tapping **Stop** interrupts it; if the interrupt doesn't
   land, the client says so instead of silently claiming success.
4. Tapping **End session** kills every pane backing that session; the row disappears and stays
   gone. If the close fails, the detail view stays open and shows the error.

## Success Criteria

- [x] SC1: `close` kills **every** pane whose session row carries the target sessionId, not just
  the first — **Verify by:** `serve-close.test.ts` over a two-pane fixture; asserts both targets
  killed and both pids tombstoned.
- [x] SC2: `close` reports failure when a pane survives the kill — **Verify by:** unit test with a
  killer that reports success but leaves the pid alive → result is `ok: false`.
- [x] SC3: `interrupt` reports whether the turn actually stopped — **Verify by:** unit test on the
  confirm helper: pane still busy after the escape window → `stopped: false`.
- [x] SC4: `computeStatus` finds an API error that is not the last row — **Verify by:**
  `sessions-status.test.ts` case: `[assistant 403, user]` → `blocked / auth_required`.
- [x] SC5: A `running` verdict on a transcript that stopped growing reads **not busy** —
  **Verify by:** `session-state.test.ts`: transcript mtime older than `STALL_MS` with a `running`
  hook state AND a `running` transcript verdict → `idle`.
- [x] SC6: A genuinely quiet-but-live turn is NOT called stalled — **Verify by:** same test, mtime
  inside the window → `running`.
- [x] SC7: The REST list and the SSE journal derive `busy` from the same function —
  **Verify by:** `sessions.ts` imports `sessionTurnState`; grep asserts no direct
  `transcriptTurnState` call remains in `sessions.ts`.
- [x] SC8: The real wedged-session transcript reads `blocked`, not `working` — **Verify by:**
  replay `dc902159-…jsonl` (copied to a fixture) through `computeStatus` + `sessionTurnState` +
  `sessionDisplayState` → `"blocked"`.
- [x] SC9: close/interrupt outcomes are durably logged — **Verify by:** hit both endpoints on the
  live server, `cat data/ops.log`.
- [x] SC10: iOS keeps the detail view open on a failed close — **Verify by:** `swift test` on a
  store-level test asserting `close` returns false and `onEnded` is not invoked.

## Platform & Stack

- **Platform:** Bun/TypeScript server + SwiftUI iOS client
- **Test frameworks:** `bun test` (server), Swift Testing / XCTest in `LFGCore` (client)

## Steps to Verify

1. `bun test` — full server suite green.
2. `cd ios/LFGCore && swift test` — client package suite green.
3. Restart the server, POST `/close` and `/interrupt`, inspect `data/ops.log`.

## Implementation Phases

### Phase 1: State truth (SC4–SC8)

- Scope: `computeStatus` scan-back; stall guard in `sessionTurnState`; point `sessions.ts` at
  `sessionTurnState`.
- Verification gate: `bun test` green including the replayed real transcript.

### Phase 2: Actions that confirm (SC1–SC3, SC9)

- Scope: `close` kills all panes + verifies + escalates; `interrupt` confirms; `data/ops.log`.
- Verification gate: `bun test` green; live endpoint probe with log output.

### Phase 3: Client honesty (SC10)

- Scope: gate `onEnded()` on the close result; surface the error.
- Verification gate: `swift test` green.

## Decision Log

**No new `"stalled"` display state.** The diagnosis proposed one. Rejected: `sessionDisplayState`
is a 2^3 parity table pinned across `session-state.ts`, `SessionState.swift`,
`session-state-parity.test.ts`, `FleetActivitySnapshot`, and `push/watcher.ts` — a fourth input
multiplies that surface for little gain. Instead a stalled turn reports `busy: false`, and SC4
makes the wedged 403 session read **blocked**, which is both accurate and already in the ladder.
A session that stalls *without* an API error reads idle — honest ("no turn in flight") and
consistent with the existing pane-less path.

**Stall threshold 15 min.** A live turn can be silent for the length of one tool call; Bash alone
permits a 10-minute timeout, so 12s (`REST_BUSY_WINDOW_MS`) would flap constantly. 15 min is the
first safely-quiet threshold.

**Stall guard in `sessionTurnState`, not the heartbeat/lease.** `state` is hook-owned per
`leases.ts`; a server write would always be newest and permanently out-vote the transcript via the
recency arbitration, and the lease is in the synced tree so a derived verdict would propagate to
the peer. Stall is a pure function of (verdict, mtime, now) — computed at read time it cannot go
stale. The pump already calls `sessionTurnState` every second, so no new clock is needed.

## Verification Evidence

Suites: `bun test` **323 pass / 0 fail** (35 files) · `swift test` **229 pass / 0 fail**.
Server restarted onto the new code (pid 57402, 10:40:58) before every live probe.

| SC | How | Result |
|---|---|---|
| SC1 | **Live.** Built a real duplicate: gave a scratch session a turn, then `--resume`d its transcript into a second pane → one sessionId, two panes (pids 62137/64100). `POST /close`. | `{"ok":true,"panes":2}`; both tmux sessions gone, **both pids dead**, 0 rows left in `/api/sessions`. Old code would have killed only `lfgdup-a`. |
| SC2 | `closing-actions.test.ts` — killer reports success, pid stays alive, `kill9` is a no-op | `killed:false, escalated:true`; endpoint maps that to `502 close failed — still running: pid …` |
| SC3 | `closing-actions.test.ts` — pane still busy across the whole confirm window | `{sent:true, stopped:false}`. Live idle-session probe returned `{"ok":true,"stopped":true}` |
| SC4 | `sessions-status.test.ts` — `[assistant 403, user]`, and past attachment/meta runs | `blocked / auth_required`. Recovery case (`[403, user, good reply]`) → `ok`, so blocked isn't a new latch |
| SC5 | `session-state.test.ts` stall guard, both layers | transcript-sourced and hook-sourced `running` both demote to `{state:"idle", stalled:true}` |
| SC6 | same file — 14 min quiet (a 10-min Bash call + slack) | stays `running` |
| SC7 | `sessions.ts` now imports `sessionTurnState`; no `transcriptTurnState` call remains there | `grep -n "turn-state\|session-state" src/sessions.ts` → import line only |
| SC8 | **Live, real data.** Replayed the actual wedged transcript (`dc902159`) through the real path | `BEFORE: busy=true blocked=false -> working` / `AFTER: busy=false blocked=true -> blocked`. Lease-free copy isolates the stall guard: transcript alone `running`, guarded `{state:"idle", source:"transcript", stalled:true}` at 56 min |
| SC9 | **Live.** `data/ops.log` after the probes | 3 rows incl. `{"op":"close","ok":true,"ms":1221,"panes":2,"outcomes":[…2 pids…]}` |
| SC10 | `swift build` + `LFGClientInterruptTests` (6 new); view gate is `if await store.close(sid) { onEnded() }` | client tests pass; app target builds via FlowDeck |

**Deviation on SC10.** The planned store-level Swift test isn't reachable: `SessionStore` lives in
the app target, not the `LFGCore` package, so `swift test` cannot import it. Covered instead by
(a) `LFGClientInterruptTests` over the client seam that carries `stopped`, and (b) making
`close` return `Bool` with `@discardableResult`, so the view's gate is a compile-checked fact.
The end-to-end "failed close keeps the sheet open" path is **unverified in the simulator** —
it needs a server that fails a close, which the live tree no longer produces.

## Bugs

### Fixed during implementation — `REAP_GRACE_MS` was too short (700ms)

The first live close returned `escalated: true` on a perfectly healthy session. Measured the
real number: a clean `claude` exits **1157 ms** after `tmux kill-pane`. A 700ms grace would have
SIGKILLed essentially every close, costing each agent its `SessionEnd` hook — the write that puts
`state: "ended"` in the lease and feeds the `closed` derivation. Raised to 2500ms and switched
from one flat sleep to a 100ms poll, so a clean exit is noticed as soon as it happens instead of
always paying the grace. Re-verified live: `killed:true, escalated:false, ms:1224`. Pinned by two
regression tests (`a slow clean exit is waited out, not escalated`, and a poll-count assertion).

_No open bugs._
