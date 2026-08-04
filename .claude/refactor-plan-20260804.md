# lfg robustness plan — 2026-08-04

Derived from `.claude/architecture-analysis-messages-and-connection.md` (written
by another session), **independently verified here**, and re-scoped after the
decision to drop the web client.

## Verification of the source analysis

Seven load-bearing claims checked against current source. All seven hold.

| Claim | Evidence |
|---|---|
| Dual delivery pipeline live | `serve.ts:2503` serves `/api/live/stream`; `web/src/App.tsx:783` consumes it; iOS is on `/api/events` |
| `LFGClient.liveStream(ids:)` dead | defined `LFGClient.swift:366`, **zero call sites** in `ios/` |
| `/messages` registered twice | `messagesResponseForSession` at `serve.ts:2291` **and** `2487` |
| Six transcript windows | 256K ×3 (`sessions.ts:925,960,1017`), 32K (`:1044`), 128K (`:1765`), configurable (`:1687`) |
| Threshold invariant is prose-only | `SessionStore.failureThreshold = 3` vs `HostProbePolicy.failureThreshold = 4`, coupled by a comment in a different module |
| `pollTimeout` rationale stale | comment says "the next tick is 3s away"; loop is `Task.sleep(for: .seconds(60))` (`SessionStore.swift:392`) — **stale 20×** |
| Status is a prose classifier | regex over assistant English, `sessions.ts:130` |

The analysis's central thesis is correct: in both subsystems a better design was
built, the predecessor was never removed, and both still run. That is why fixes
appear not to stick.

## Framing: this is deletion, not refactoring

Every item below removes the **older of two systems that both run today**. None
is a rewrite. This matters because the newer system is already in production and
proven, so each step is a subtraction with a known-good fallback.

Explicitly **not** in scope: rewriting `sendq.ts`. Its 21 retrospective comments
are load-bearing knowledge, and both this analysis and today's independent
send-path work concluded its confirm strategy (transcript growth when idle,
composer-cleared when busy) is **sound**. Today's real fix was a single tri-state
check, not an architecture change. A "clean rewrite" here would re-earn every one
of those 21 traps.

## Findings that change the plan

1. **The web client is not in use.** The 8 established connections to the Pro's
   `:8766` come from `lfg`/`bun.exe` processes on the Air — host-to-host traffic,
   not a browser. `web/dist` last built Jul 31; last `web/src` commit Jul 31.
   Confirmed with Eugene: **delete it.** Item 1 becomes a deletion, not a port.
2. **The Air runs a 4-day-stale server.** Its `serve` process started
   `Jul 31 22:52:03`, while its checkout (Syncthing-synced, identical to the
   Pro's including uncommitted work) carries `sendq.ts` from `Aug 4 15:35`. So
   **none of today's send-path fixes are live on the Air** — symptoms 2 and 3
   persist there regardless of anything shipped to the phone. It is supervised
   by `serve-forever` (pid 18971) and SSH works, so a restart is safe; it has 5
   live sessions whose in-memory tracking a restart would drop.

## Concurrency hazard

Three other agents are working in this repo right now, and `serve.ts` is the
file every stage touches. Project CLAUDE.md: keep edits to shared files minimal
and additive, and check for concurrent work first. **Stage 1 deletes ~300 lines
from `serve.ts`** — it must be done in one short, uninterrupted pass, or in a
worktree and merged, not dribbled across a long session.

## Stages

### Stage 0 — free wins (minutes, no risk)
- Delete the duplicate `/messages` route (`serve.ts:2487`; dead, unreachable).
- Fix `pollTimeout`'s stale "3s away" rationale → 60s.
- Fix the contradicted comment at `SessionStore.swift:163-167`.

### Stage 1 — retire the second delivery pipeline (highest value)
Delete, in this order:
- `web/` (own package, 9,213 LOC in `web/src`)
- `/api/live/stream` (`serve.ts:2503`) + its per-connection tail/pane pump
- `/api/sessions/:id/stream` + its pump
- static web serving: `WEB_DIR`, `INDEX_PATH`, `/sw.js`, `/assets/*`,
  manifest/icon routes (`serve.ts:497-513, 1016-1075`)
- `LFGClient.liveStream(ids:)` + its `LiveEvent` plumbing if unused elsewhere
- `marked` + `msgWithHtml` + `renderReportHtml` — server-side HTML rendering
  existed only for the web client; iOS decodes `html` and never reads it

Result: one delivery path, server CPU from O(connections × sessions) to
O(sessions), and **the backend reaches zero npm dependencies**.

Risk: `/` stops serving anything. Acceptable — no browser client remains.

### Stage 2 — one host health state machine (fixes the symptom you feel)
Replace ~8 representations of "is this host up" with a single `HostState`
(`connecting / live / degraded(since:) / offline(since:) / noNetwork`) owned by
`SessionStore`. `HostLink` reports **events** (`connected`, `elementReceived`,
`failed`, `closed`) and holds no health opinion. Deletes the
`HostLink.unhealthySince` / `SessionStore.unhealthySinceByHost` dual clock —
a second clock added because the first lived in an object with the wrong
lifetime.

This is the durable fix for the disconnect banner. Build 202608041554 shipped a
*patch* (C1–C5); this makes "recovered" a single assertable transition.

Also here: one policy struct, cadence in **seconds not ticks**, and
`probeThreshold = displayThreshold + 1` derived in code, with a test that fails
when they cross.

### Stage 3 — one transcript reader
A `Transcript` module owning all file access: `tail(n)`, `head(n)`,
`page(before, limit)`, `scanBack(predicate)`, with a window that **grows until it
finds the answer or hits the file head** instead of six fixed constants that fail
silently. Then `listSessions()` does **one** read per session instead of four.

At ~15 sessions that is ~60 slices of up to 256 KB per pass on the single Bun
event loop — the loop CLAUDE.md already flags as saturable, against transcripts
reaching 18 MB.

### Stage 4 — structured session status
Stop gating `blocked` on regex-matching assistant English. Use the transcript's
`isApiErrorMessage` flag plus the error `type`/`code`. Treat "unknown blocked
reason" as a first-class state showing the raw error. Keep regexes only as a
display labeller, never as the gate.

## Recommended order

Stage 0 → **Stage 1** → Stage 2 → Stage 3 → Stage 4.

Stage 1 first because it is now a pure deletion (cheapest it will ever be), it
removes the "fixed bugs come back" class outright, and it shrinks the surface
every later stage has to touch.

Separately and immediately: **restart the Air's server** — unrelated to the
refactor, but it is the difference between today's send fixes being live on one
host or both.

---

## Status — 2026-08-04, end of the refactor session

| Stage | Commit | State |
|---|---|---|
| 0 — free wins | `daafd81` | **done** |
| 1 — retire the second pipeline | `883efff` | **done** — 11,408 lines deleted |
| 3 — one transcript reader | `8da0413` | **done** |
| 4 — structured status | `e295dcf` | **done** — found a real invisible outage (`auth_required`) |
| 2a — derive the probe policy | `56fb61e` | **done** |
| 2b — host state machine, pure core | `bf637ba` | **done**, 13 tests, nothing consumes it yet |
| 2c — wire the state machine in | — | **not started**, blocked on one decision below |

### The open decision blocking 2c

`reachabilityByHost` is read in ~10 places (all `== .ok`) and written in 5.
The plan was to make `hostStateByHost` the authority and derive
`reachabilityByHost` from it, so no reader changes. That works for every case
except one:

**What does `degraded` display as?** The old code's rule is *"within the grace
window, keep the previous value"* (`evaluateStoredUnhealthy` returns early and
leaves the map untouched). A derived projection has no "previous".

- `degraded` → `.ok` is right when we degraded **from live** — that is the whole
  point of the grace window, not alarming the user about a blip.
- `degraded` → `.ok` is **wrong** when the host has never connected: at cold
  launch a first-dial failure would claim a host is reachable, which enables
  sends against a host that has never answered.

Three ways out, in my order of preference:

1. **Have the state carry it** — `degraded(since:reason:wasLive:)`, or track
   `everLive` per host in the store. Honest and explicit; slightly uglier type.
2. **Change the ~10 readers to consume `HostState` directly** and delete
   `reachabilityByHost` entirely. This is the correct end state — no projection,
   no "keep previous" — but it touches the views (`OfflineComposerNotice`,
   `Components.swift`) and is a materially bigger diff.
3. Keep a remembered last-displayed value. Rejected: that is a second piece of
   state, i.e. the exact pattern this stage exists to delete.

### Why 2c was not attempted blind

It interacts with `isReconnecting` and the tri-state "Connecting…" from the
instant-reconnect work, so it is UI-affecting and needs live verification of
**both** paths — a blip from a live host, and a cold launch against a host that
never answers. Per the repo's own rule (`verify-ui-by-tapping`,
`verify-real-seam-not-mocks`) a green unit suite is not "verified" for this.
Guessing the display semantics and shipping it unverified would reproduce the
class of bug the stage exists to remove.

---

## Stage 2c — done, 2026-08-04

Resolved the open question by picking **option 2**: `reachabilityByHost` is
deleted, and the views read `hostStateByHost` / `fleetState` directly.

The `degraded` display problem turned out to have a better answer than any of
the three options listed above. The UI already had a **tri-state** connection
indicator (`connected / connecting / offline`), added by the instant-reconnect
work so that "unknown" would stop rendering as "Offline" at launch. `degraded`
maps straight onto its middle case: a host that is failing but still inside its
grace window is **connecting** — not connected, not offline. No projection, no
remembered previous value, no `wasLive` flag. The true state, and the UI already
had a word for it.

### Live verification (`ios/design/verify-stage2-20260804/`)

Driven through the real onboarding and settings UI on the session simulator,
against the real server:

| # | Step | Result |
|---|---|---|
| 1 | Point at the live host | **Connected**, green dot, sessions load |
| 2 | Repoint at a dead port | **yellow** dot — degraded, not "down" |
| 3 | Same moment, main list | **"Connecting…"** — the false-offline regression is gone |
| 4 | Wait out the 30s grace | **"Offline"** + "Host unreachable" banner carrying the failure reason; dot turns orange |
| 5 | Make the host answer again | **Connected** immediately, banner gone |

Step 5 used a TCP proxy putting the real server on the dead port, because the
"Save" nav-bar button is absent from the accessibility tree (the toolbar-button
trap recorded in `ios/CLAUDE.md`). That made the recovery genuine rather than a
settings edit.

### A bug the build could not have caught

`link.onSignal` was initially never wired to the store. Everything compiled —
it is an optional closure — but the entire state machine was inert: every host
would have sat at `.unknown` forever, no banner would ever appear, and `isLive`
would have been permanently false, blocking sends. Found by asking "what proves
this is connected?" rather than by the green build. Sequence tests now cover the
folds that wiring feeds.
