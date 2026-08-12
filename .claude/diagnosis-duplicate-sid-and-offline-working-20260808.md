# Two bugs: phantom "reelly" notifications, and offline-host sessions stuck "Working"

Session 20260808-103733. Both reproduced from live state on `Eugenes-MacBook-Pro`, not theorised.

---

## Bug 1 — a session id owned by TWO live processes push-spams every 10s

### Symptom

Notifications keep arriving titled with the **reelly** session, saying it needs
input, when reelly is not asking anything.

### Ground truth

`GET /api/sessions` returns **23 rows for 21 distinct session ids**:

```
d1a3496d | reelly | pid 36372 | pane cy-225024-35837:0.0
d1a3496d | reelly | pid 18071 | pane cy-175401-17735:0.0     <-- same sessionId
dcf548c0 | gbrain | pid 28012 | pane cy-171503-27234:0.0
dcf548c0 | gbrain | pid 54804 | pane cy-172153-54414:0.0     <-- same sessionId
```

This is not lfg mis-resolving. Claude Code itself wrote two authoritative
pidfiles naming the same session:

```jsonc
// ~/.claude/sessions/36372.json   (proc start Fri Aug 7 14:50)
{"sessionId":"d1a3496d-…","status":"waiting","waitingFor":"input needed"}
// ~/.claude/sessions/18071.json   (proc start Sat Aug 8 09:54)
{"sessionId":"d1a3496d-…","status":"idle"}
```

Two live `claude` processes are attached to one conversation — the older pane is
parked at a prompt, the newer one is idle.

Independent corroboration in `~/.lfg/liveactivity.log`, where one card renders
the same sid twice:

```
"rows":["d1a3496d:needsInput","dcf548c0:working","dcf548c0:working"]
```

### Mechanism

`runPushTick` (`src/push/watcher.ts`) keys its `prior` memory by **sessionId**,
and iterates rows. Two rows, one key, so each tick overwrites the other's memory:

| tick | row observed | `prev.promptPresent` | reducer verdict |
| --- | --- | --- | --- |
| n | pid 36372 (at a prompt) | false (left by 18071) | **`needs-input` → PUSH** |
| n | pid 18071 (idle) | true (just left by 36372) | prompt vanished, no event |
| n+1 | pid 36372 | false again | **`needs-input` → PUSH** |

The pair oscillates forever. `DEDUPE_MS` (10s) is the only thing throttling it,
so the phone gets "🙋 reelly — waiting for your input" every ten seconds while
the session the user opens is idle. The same collision also duplicates rows in
the Live Activity card and burns one of its 3 row slots.

`resolvePaneOwners` already guards the mirror-image collision (N sessions → 1
pane) but nothing guarded N pids → 1 session id.

### Fix

`dedupeBySessionId` in `src/sessions.ts`, applied just before
`resolvePaneOwners`. One row per session id; the winner is the process that most
recently attached (a live pane beats a paneless row, then newest `startedAt` —
`lastActivityAt` cannot discriminate because both rows read the same
transcript). Losers are **dropped**, not blanked: every downstream consumer
(`prior`, journal deltas, client `busy[sid]`/`prompts[sid]`, fleet rows) is keyed
by session id and has no coherent way to hold two.

---

## Bug 2 — sessions on an offline host keep counting as "Working"

### Symptom

When the Air is down, the list still shows a few of its sessions running.

### Ground truth

The Air is unreachable right now (`tailscale ping` times out, `curl :8766`
returns 000) — the exact condition described.

### Mechanism

Deliberate, and correct as far as it goes: `lastSessionsByHost`
(`SessionStore.swift:303`) keeps each host's last good snapshot so a blip doesn't
make its sessions vanish. `rebuildSessions` merges those stale rows into
`sessions`, and the busy-seeding loop at :1757 re-asserts each stale row's
`busy: true` into `busy[sid]` on every rebuild.

`group(for:)` (:2046) then never asks whether the owning host is reachable:

```swift
if s.closed { return .closed }
switch SessionDisplayState.resolve(promptPresent:blocked:busy:) { … }
```

So a session that was busy when the Air went down stays in **Working**, and in
`runningCount`, indefinitely. The store already knows better — `isOffline(_:)`
exists at :411 and is wired to the row's dim + orange chip and the disabled
composer — but it stops short of the one thing the user actually reads: the
group and the count.

The state is genuinely *unknown*, not *running*. Claiming "Working" asserts a
fact the client cannot observe.

### Fix

A dedicated `offline` group. Folding these into `idle` would trade one lie for a
quieter one; a group says the true thing — these sessions exist, on a host you
cannot reach — and removes them from `runningCount` and from "Needs you", which
is where the false urgency lives.

`closed` and `offline` are both host-topology tiers the server cannot compute
(hosts are client-side config), so they sit outside the shared
`SessionDisplayState` ladder, above it, in that order: a closed session is
host-agnostic and revivable anywhere, so it is never offline.
