# Track A (Phase 1 + 2) — Soak Test Plan

**Date:** 2026-07-10. Spec: `.claude/brainstorm/multihost-first-rearchitecture.md` §4–§5, §10.
Phase 1 gates (SC1–SC8) passed against sim + scratch server (`phase1-connectivity-core.md`);
Phase 2 sub-tasks A–D2 each verified with device-only checkpoints deferred (`phase2-background-continuity.md`).
What remains is the plan's one non-compressible step: **days of real phone use on real cellular** — plus the
specific behaviors below that only a device can prove.

## Preconditions — state as of 2026-07-10 evening

| Item | Status |
|---|---|
| Phone on today's TestFlight build (uploaded 19:27, includes Phase 1 client, Phase 2 B/C/D2, LFGWidgets) | ✅ install it if you haven't |
| Pro server current (`6c9ab4a`, pid 91597, started 19:43) | ✅ |
| Air server current + backpressure fix (the wedge from `diagnosis-air-still-disconnecting-post-phase1.md` is deployed; pid 93898) | ✅ |
| `LFG_LIVE_ACTIVITIES=1` on both hosts | ✅ enabled today |
| APNs configured on both hosts | ✅ |
| **Router: NAT-PMP or forward `udp/41641` to the Air** | ❌ **open — the only remaining Phase 0 item.** 10 min of router config; directly reduces path-flap frequency (§4.2). Only you can do this. |

## Part 1 — Deliberate behaviors to exercise (one sitting, ~20 min)

Each maps to a Phase 1 acceptance target. Do it, watch for the expected behavior; anything else is a bug worth a timestamp.

| # | Do | Expect (new behavior) | Old behavior this replaces |
|---|---|---|---|
| 1.1 | Open the app, then rapidly open/close 5+ sessions, create a new one, send a message | Transcripts flow instantly; **no reconnect spinner, no list flicker** | Every open/close/create tore down and rebuilt the host stream |
| 1.2 | Airplane mode ON for ~15s mid-transcript, then OFF | Stream resumes within ~3s, **no banner**, no missed lines | Blip surfaced as "host unreachable" + backfill glitches |
| 1.3 | Airplane mode ON for ~60s, then OFF | Banner appears around the 30s mark naming the host, clears within seconds of recovery, transcript has **zero gaps** | Banner timing arbitrary; messages in the gap lost beyond 40-msg backfill |
| 1.4 | Close the Air's lid (or let it sleep) while using Pro sessions | Pro experience completely unaffected; Air marked unreachable after ~30s, **only the Air** | One dead host stalled everything ~15s per refresh |
| 1.5 | Edit the Air's entry in Settings → hosts (touch and re-save) | Only the Air's connection restarts; Pro stream never blips | Any Settings edit wiped and rebuilt ALL connections. *This is Phase 1's SC6 — never live-verified, code-shape only.* |
| 1.6 | Scroll around an idle session, background the app, have someone/something write to a DIFFERENT idle session, return | That session shows unread | mtime corruption + sticky `focusedID` swallowed unread on idle sessions |

## Part 2 — Background continuity (Phase 2, needs the real device)

| # | Do | Expect | Notes |
|---|---|---|---|
| 2.1 | Type a send, hit send, **immediately lock the phone** | Message lands exactly once (verify in the transcript later); bubble resolved next open | Gate C1 passed on sim; this is the device confirmation |
| 2.2 | Send on flaky signal (elevator, parking garage), pocket the phone | Same — the system daemon completes it; no duplicate, no loss | C2/C3 analog. Known limit: **force-quitting the app cancels in-flight sends** (iOS policy, accepted until Track B outbox) |
| 2.3 | Kick off a long agent run, background the app for 10+ min, then unlock | App is **current at unlock — no catch-up spinner** (content-available pushes kept the cursor warm) | Device checkpoint from Phase 2B: real APNs (unlike `simctl push`) must drive the background page-fetch |
| 2.4 | Kick off a run, lock the phone, don't touch it | **Live Activity appears on the lock screen** (push-to-start), tracks status while the app has no process, updates as the agent works, ends when finished | First-ever live test — flag enabled today. Update-token path + widget rendering were unverifiable on sim |
| 2.5 | Let a run finish while backgrounded | ONE "finished" push, **arriving when it's actually done** — including through Codex delegations (today's busy fix) | Premature "finished" pushes mid-delegation were a symptom of the busy bug fixed today |

## Part 3 — The soak itself (days, passive)

The original complaints were *"flaky over days of real cellular use"* — so the pass condition is experiential:

- **Watch for:** any "host unreachable" while you know the host is up · any session stuck "Working"/"Idle" wrongly · any message you sent that never landed · any transcript gap · any unread that never appeared · Live Activities that stall or never end · app memory pressure after days (Phase 1 residual: per-session transcript cache is unbounded until Track B).
- **When something looks wrong, capture:** rough timestamp + which host + what you were doing (cellular/wifi, foreground/background). I can correlate against server logs — the journal, `[events] connect/page` lines, and `data/sendq.log` make every one of these diagnosable now.
- **Server-side checks I can run during the soak** (ask anytime): phone's background page-fetches appearing in logs (`[events] page` after pushes — Phase 2B's device checkpoint), Live Activity token registrations in `live-activity-tokens.json`, journal head/cursor health, Air event-loop responsiveness.

## Sim pass results (2026-07-10 evening — live tailnet, Pro + Air, real ts.net URLs)

Run by Claude in a dedicated simulator (`lfg-0f84a15e`) configured with both hosts'
MagicDNS HTTPS URLs. Evidence frames: `.claude/feature/track-a-sim-evidence/`.
Outages were induced by SIGSTOP/SIGCONT on the Air's serve (the black-hole case);
zero-gap checks used marker messages appended to a throwaway Air session's transcript mid-outage.

| Gate | Result | Evidence |
|---|---|---|
| 1.1 zero stream rebuilds under churn (4 opens + 3 backs, live transcript) | **PASS** — connect count unchanged on BOTH hosts (Pro 48→48, Air 20→20) | server logs |
| 1.2 short blip invisible (15s) | **PASS** — no banner, stream resumed, marker ALPHA delivered exactly once | screenshots |
| 1.3 sustained outage honest + lossless (60s) | **PASS** — Air chip orange + per-session ⚠ between T+50–60 (matches Phase 1's shipped timing: ~20s detect + 30s grace), cleared within ~10s of recovery; markers ALPHA+BRAVO each delivered exactly once, zero gaps, zero duplicates across two outages | `banner-t*.jpg` |
| 1.4 healthy host unaffected during other host's outage | **PASS** — Pro rows kept ticking ("12s ago") in the same frame as the orange Air chip | `banner-t065`-era frame |
| 1.5 Settings-edit link isolation (first live verification of SC6) | **PASS** — open Air editor → Save → Done produced ZERO reconnects on both hosts (no-op edit correctly restarts nothing; Pro untouched) | connect counts 49→49, 28→28 |
| 1.6 new message on idle session surfaces as Unread | **FAIL** — see B2 | — |
| Bonus: busy fix live | my working session showed WORKING via real tailnet; delegation-busy already probed earlier | screenshot |
| Bonus: Live Activities on SIM (device checkpoint pulled forward) | **PASS** — push-to-start rendered a lock-screen card for a running session ("ok start phase 1 · working"), and the elapsed state UPDATED across observations (2:35 → 3:54 → 11:36); real APNs alert push also rendered in-app | `live-activity-lockscreen.jpg`, `live-activity-updating.jpg` |

### Bugs found (client, in-memory merge path) — **BOTH FIXED + live-verified 2026-07-10 evening**

Root causes (diagnosed by Codex, patch applied by Claude after Codex's sandbox went read-only):

- **B1 root cause:** `closedCache` was rebuilt on a slow cadence against a *previous* rebuild's
  `liveIds`, while the live merge recomputed later — a session could be excluded from the closed
  fallback by stale live ownership while also absent from the current live list (present in
  neither bucket). Fix: `MultiHost.reconcileSessionList` computes live merge + optimistic +
  closed exclusion in ONE pass against the same live-id set; `rebuildSessions` uses it.
- **B2 root cause:** `SessionDetailView` set `store.focus(sid)` on open but never cleared it on
  disappear — `focusedID` outlived the view, and both the stream handler and `rebuildSessions`
  kept auto-marking every later message as seen, so idle sessions never surfaced as Unread.
  (This is the exact sticky-focus hole §7.4 of the rearchitecture doc set out to close.) Fix:
  guarded `blur(sid)` on `.onDisappear` via pure `SessionFocus` helpers.

Verification: 7 new LFGCore tests (115/115 green), `bun test` 107/107, and the live repro re-run
on the patched build — row stayed in the list THROUGH a 60s Air outage (closed fallback), returned
live after recovery, and the mid-outage marker surfaced it in UNREAD with the dot
(`track-a-sim-evidence/b1b2-fixed-unread.jpg`).

- **B1 — session vanishes from the list after its host recovers from an outage.** The throwaway
  Air session was present at bootstrap, disappeared from the sim's list during the blip sequence,
  and never returned despite multiple 60s reconcile cycles — while `GET /api/sessions` on the Air
  kept returning a perfectly normal row. A fresh app launch restored it. Likely the same root as
  the already-open "list view does not show all the sessions" investigation (twin session) — this
  is a clean reproduction recipe for it: create session on host B → SIGSTOP host B's serve 60s →
  SIGCONT → row gone until relaunch.
- **B2 — unread never fired for a new message on an idle session.** Marker CHARLIE (well-formed
  assistant line; the server's `last` preview showed it correctly) arrived while the list was
  open and the session unfocused. The row never surfaced in UNREAD — even after relaunch it sat
  in IDLE as read. May share a root with B1 (the row wasn't in the in-memory list when the msg
  event arrived, so there was nothing to mark unread; post-relaunch read-state then keyed off…
  needs diagnosis). Caveat: the message was file-appended, not agent-produced — reproduce once
  with a real agent turn before deep-diving.

Both bugs are **client merge/read-state issues, not transport** — the Phase 1 transport promises
(no self-teardowns, lossless cursor resume, honest per-host reporting) all held over the live tailnet.

## Explicitly OUT of scope (Track B — don't count these as Phase 1/2 failures)

- **Cold launch with all hosts down shows a blank list** — offline store is Phase 4.
- **Force-quit kills an in-flight send** — durable outbox + clientId idempotency is Phase 3/5.
- **Double-resume divergence** (resuming the same session from both hosts forks it) — leases are Phase 6.
- Occasional path flaps on cellular still *happen* (physics) — Track A's promise is they're **invisible** (1.2), not impossible.

## Exit criteria

Track A is "verified" when: Parts 1–2 all behave as expected, and several days of normal use produce
zero entries in the Part 3 watch-list (or only entries traceable to Track B gaps above). Then Track B
(durable sends → offline store → outbox → leases → cleanup) starts on a verified foundation.
