# Diagnosis — Air still flapping after Phase 1

**Date:** 2026-07-10
**Question:** Is the Air running the latest Phase-1 lfg server? Why does it still disconnect while the Pro is stable?

---

## Verdict

**No — the Air cannot be running the latest server. Phase 1 was never pushed.** The Pro is 14
commits ahead of `origin/main`, and every Phase-1 commit — including `421e07d`, the commit whose
subject line is literally *"fixes Air wedge"* — exists only on this machine.

The Air is running Phase-1 server code **without** the backpressure fix (it got the code by a
first deploy before the fix existed), so it is wedging exactly as `421e07d` describes. The Pro is
stable because its running process was started one second *after* the fix landed.

---

## Evidence

### 1. The Air's server process is bound but wedged (measured, not inferred)

| Probe | Result | Meaning |
|---|---|---|
| `nc 100.75.162.40 22` | **Connection refused** (RST) | Host TCP stack alive, awake, answering |
| `nc 100.75.162.40 80` | **Connection refused** (RST) | Same — no listener, honest RST |
| `nc 100.75.162.40 8766` | **Operation timed out** (no RST) | A listener **exists**; its accept queue is full → SYNs dropped |
| `nc 100.75.162.40 443` | **succeeded** | `tailscale serve` is up |
| `https://…ts.net/api/ping` | **502 after ~8.0s** | serve proxied to the backend over **loopback** and waited — backend never answered |
| `tailscale ping air` | **pong in 6ms, direct** | Network path is perfect |

Ninety seconds of polling `/api/ping` at 2 Hz: **zero** non-502 responses.

The RST-vs-timeout split is the whole diagnosis. A port with nothing listening RSTs (22, 80). Port
8766 silently drops SYNs, which only happens when a socket *is* bound and nobody is calling
`accept()` — a blocked event loop.

**Firewall theory disconfirmed.** macOS ALF could explain the dropped SYNs on 8766, but not the
502: `tailscale serve` reaches the backend over **loopback**, which ALF does not filter. Both paths
are dead, so the process — not the network — is the fault. (Per memory `tailscale-ping-is-ground-truth`,
the tailnet path was verified good independently.)

**Host sleep disconfirmed.** A sleeping peer black-holes *everything*; ports 22 and 80 answered.

### 2. The mechanism, already written down in our own git history

`421e07d` (local-only, unpushed):

> The interval-based ticks fired `pollOne` for every session in parallel with no backpressure: on a
> machine where one tick's pane-scrapes take >1s, the next tick stacks more spawns on the
> still-running ones, unboundedly, until the single event loop drowns. **This wedged the Air's
> server hard on first deploy (TCP accepted via kernel backlog, HTTP never answered — the exact
> signature) while the faster Pro stayed ahead of the same load.**

Pre-fix shape (what the Air runs) — fire-and-forget into a fixed interval:

```js
const pollTimer = setInterval(() => {
  for (const w of watched.values()) void pollOne(w);   // no await, no backpressure
}, POLL_TICK_MS);                                       // next tick fires regardless
```

Post-fix shape (what the Pro runs) — serialized self-scheduling loop:

```js
const pollLoop = async () => {
  for (const w of watched.values()) { if (stopped) return; await pollOne(w); }
  pollTimer = setTimeout(pollLoop, POLL_TICK_MS);       // only after finishing
};
```

Each `pollOne` spawns a `tmux capture-pane`. The pump is one global loop over every session the
host executes. On the slower Air, one tick's scrapes exceed 1000ms, so tick N+1 stacks another
full set of spawns on the unfinished ones. It compounds until the single Bun event loop drowns —
and it never accepts a connection again.

### 3. Why the Pro is stable — one second of luck

```
421e07d  journal-pump backpressure fix   2026-07-10 03:46:49 +0800
748290d  merge                            2026-07-10 03:46:50 +0800
PID 17020  bun run src/cli.ts serve      Fri Jul 10 03:46:51 2026   <== started 1s after the fix
```

The Pro's live process picked up the fix on the restart that immediately followed the merge. It
would also have survived without it (the commit says the faster machine "stayed ahead of the same
load") — but it is *definitively* running the fixed code, and it has been up 7h38m.

### 4. Why the Air "connects occasionally"

`scripts/serve-forever.sh` restarts the child **only when it exits**. A wedged process never
exits, so the supervisor cannot rescue it. The intermittent healthy windows are almost certainly
Bun segfaulting under long-lived SSE (the documented reason `serve-forever.sh` exists) → restart →
a fresh process answers for as long as it takes the pump pileup to drown it again.

This is not a client-side flap. The server is genuinely gone for minutes at a time.

---

## The deploy gap, generalized

The project CLAUDE.md warns about *running code lagging source*. This is the sibling failure:
**source lagging on the other host, because it was never pushed.**

```
$ git rev-list --left-right --count origin/main...HEAD
0	14
$ git merge-base --is-ancestor 3a926af origin/main   # phase 1 journal
NO
$ git merge-base --is-ancestor 421e07d origin/main   # the Air-wedge fix
NO
```

`origin/main` still tops out at `8a53b86 serve-forever: revert to loopback default`. The Air could
pull right now and get **nothing**. And `serve-forever.sh` never pulls, so even a pushed fix needs a
manual deploy.

Phase 1 is a *multi-host* feature that was verified on exactly one host.

---

## Fix

1. **Push.** `git push origin main` — 14 commits, including the fix. (Not done: needs Eugene's
   explicit go-ahead per Safety Rails.)
2. **Get a shell on the Air.** `ssh` is refused (Remote Login off) and Tailscale SSH is not enabled.
   Either enable Remote Login in System Settings → General → Sharing, or run `tailscale set --ssh`
   on the Air. Without one of these, the Air is undeployable and undebuggable from here — worth
   fixing permanently, not just for today.
3. **On the Air:** `git pull && ` restart the `serve-forever.sh` supervisor (kill the wedged child;
   the supervisor respawns it).
4. **Then re-probe:** `nc -v <air> 8766` must connect, and `/api/ping` must return 200 — that
   endpoint exists only in Phase 1, so a 200 doubles as the version fingerprint.

## Follow-ups worth doing

- **Make the wedge self-healing.** A wedged process is invisible to `serve-forever.sh`. Add a
  watchdog that curls `/api/ping` on loopback every 30s and `kill -9`s the child after N
  consecutive failures. Backpressure prevents *this* pileup; a watchdog covers the next one.
- **Cap pump concurrency explicitly.** Serialization fixes the pileup but makes cadence scale
  linearly with session count. A bounded worker pool (say 4) would hold cadence on the Air.
- **Never `void` an async call inside a repeating timer.** That is the whole bug class.
