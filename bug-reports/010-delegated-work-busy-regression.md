# Bug 010: Delegated-work busy fold pins sessions "Working" and breaks interrupt

## Status: FIXED (server); client error-surfacing deferred

## Description

Since `feat: expose delegated session work` (a7bf99c), sessions with finished
subagents or long-lived background shells stay "Working" on every client
forever, suppress their own finished/needs-input pushes, and — because the iOS
Stop action and the server's interrupt confirmation both key off the same
busy signal — codex interrupts usually appear to do nothing.

## Steps to Reproduce

1. In a Claude session, run a synchronous subagent (e.g. Explore) to completion,
   or start a dev server with `run_in_background` in a codex session.
2. Let the session's own turn end.
3. **Observed:** the session stays "Working" indefinitely (REST, journal, push,
   Live Activity); Stop is offered and does nothing; no finished push ever fires.
4. **Expected:** status returns to idle when the turn and delegated agents are
   done; background shells surface as a badge, not as "Working"; interrupt works.

## Root Cause

Four coupled defects:

1. **Sync-subagent latch.** A child agent's completion is only read from
   `<task-notification>` rows, which Claude Code writes for async launches
   only. A synchronous agent's completion lives in its `tool_result` row
   (`toolUseResult.{agentId,status}`), which `readParentEvents` filters out —
   so `status ?? "running"` latches forever (src/subagents.ts:285). Verified:
   five Explore agents finished in July still report "running".
2. **Background shells promote `busy`.** `busyWithRunningWork` ORs
   `runningBackgroundProcessCount` into `busy` in all four seams (REST list,
   journal pump x2, push watcher), and the codex pane `isBusy` counts
   background terminals (src/tmux.ts:1162). A dev server pins the session
   "Working" for its whole lifetime; live evidence: sessions 01a023cc/01a01ab8,
   idle at the composer with `task_complete` rollout markers, shown Running.
3. **Interrupt is unconfirmable and unobservable.** One un-retried Escape
   (repo documents lone-ESC buffering in dismissPrompt), a 1.5s confirm window,
   a confirm predicate that can never clear while a background terminal is on
   screen, no logging on the 404/409 guards, and a client that renders no
   errors.
4. **Per-tick transcript scans.** `runningBackgroundProcessCounts` streams
   every live session's transcript on cache miss — including codex rollouts
   that can never contain `backgroundTaskId` (measured 858ms for a 536MB
   rollout) — on the single event loop, every scan.

## Success Criteria

- [x] SC1: A synchronous subagent's `tool_result` completion terminates its
  status; a launch with no completion record and no recent child activity
  degrades to `unknown` instead of latching `running`. — **Verify by:**
  `src/subagents.test.ts` new cases; live probe of transcript `86865f2b-…`
  returning `completed`.
- [x] SC2: Background shells/terminals never promote `busy` anywhere (REST,
  journal, push, codex pane isBusy) while their badge counts keep flowing. —
  **Verify by:** updated fold + pane tests; live: 01a023cc/01a01ab8 read idle
  with `bg=1` after restart.
- [x] SC3: Running child agents still promote `busy`, and their completion now
  clears it (so the finished push fires). — **Verify by:** fold tests +
  watcher transition test.
- [x] SC4: Interrupt re-sends Escape while the pane still reads busy, allows
  ~5s to unwind, and every interrupt attempt (including 404/409) is logged. —
  **Verify by:** `closing-actions.test.ts` retry cases; ops.log entries on a
  live interrupt.
- [x] SC5: Codex rollouts are never streamed by the background-task scanner. —
  **Verify by:** enrichment gate + latency spot-check of `/api/sessions`.
- [x] SC6 (found during verification): a rollout a codex process merely READS
  is never treated as ownership, so a freshly spawned session cannot bind (and
  permanently registry-latch) onto a days-old rollout. — **Verify by:**
  `parseOpenCodexRollouts` mode tests; live re-bind of the scratch session.

## Investigation Log

### Attempt 1

**Hypothesis:** All six iPhone-client symptoms trace to a small set of server
regressions from the delegated-work feature plus transport outages.

**Changes:** None (triage). Two parallel investigations mapped the pipeline and
produced the four root causes above with file:line evidence.

**Result:** Confirmed live (false-Running codex rows, jittery 0.17–1.1s
listSessions). Proceeding to fix as designed above.

### Attempt 2

**Changes:** Background counts removed from every busy fold and from codex pane
`isBusy` (badge only); `toolUseResult.{agentId,status}` read as a lifecycle
source; 30-min staleness backstop for lifecycle-less "running" children;
`parentEvents` made incremental (offset + partial-line carry, journal-pump's
pattern) and `transcriptTimes` cached per signature; codex sessions excluded
from Claude-transcript scanning; interrupt re-sends Escape each 1.5s of
continued busy inside a 5s window and logs its 404/409 guard exits.

**Result:** Full `bun test` 690/690, `bunx tsc --noEmit` clean. Supervised
restart at 11:49. Live: the two pinned codex rows (`01a023cc`, `01a01ab8`)
dropped to `busy=false` with `bg=1` badges; the latched July Explore agent in
transcript `86865f2b-…` reads `completed`; enrichment now measures ~0ms atop
the base scan (the residual ~1.1s spikes are the pre-existing uncached
ps/lsof/tmux scan — follow-up, not this bug).

### Attempt 3 — new spawn-time misbinding found during live verification

**Hypothesis:** interrupt could be live-verified on a scratch codex session.

**Result:** The scratch session (`lfg-f88d49`) spawned busy-on-pane but
`busy=false` on the API: it had been bound to rollout `01a01ad6` from
**two days earlier** while the process was writing `01a0279a`. Root cause 5:
codex transiently opens OTHER sessions' rollouts **read-only** at startup
(history/picker); the batched `lsof -Fn` snapshot had no access-mode field, so
`pickOpenCodexThread` treated the read descriptor as ownership and
`patchManaged` made the wrong id permanent — the managed registry outranks
every later binding signal. This is the residual form of the "codex status
flapping" complaint surviving the codex-status-stability fix.

**Changes:** `lsof -Fan` + access-mode parsing in `parseOpenCodexRollouts`:
a rollout open `r` (read-only) is never ownership; unknown mode stays owned
(Linux `/proc` reports none). Regression tests added. Poisoned registry record
repaired by hand; audit of all live managed codex records found no others.

**Result:** After restart the scratch session bound to its real rollout and
tracked busy correctly. Full suite 692/692. Live interrupt: mid-turn codex
(meter up, background terminal on screen — the previously-poisoning shape)
aborted on the first Escape — `{ok:true, stopped:true}` in 0.3s, rollout tail
`turn_aborted`, ops.log entry written. Ten-scan stability probe: no codex busy
edges; only genuinely-working sessions appear. Scratch session closed.

## Design decisions

- Child agents KEEP promoting `busy`: "agents done → status clears → finished
  push fires" is the wanted behavior; the latch was the bug, not the fold.
- Background shells are a badge, never `busy`: a dev server is not a turn.
  Same for codex "N background terminals running" in pane isBusy — that line
  also made sendq treat idle codex sessions as busy.
- Staleness backstop for crashed agents: `running` with no completion record
  and no child-transcript activity for 30 min reads as `unknown` (not
  terminal, not running). 30 min because a single silent Bash tool call
  (a build) can legitimately run >10 min. Applied outside the sidecar cache so
  it takes effect without a file change.
- Interrupt mirrors dismissPrompt's retry shape: re-send Escape only while the
  pane still reads busy (never onto an idle composer — second Esc opens
  rewind/backtrack), 5s total window for codex to unwind an in-flight tool.

## Deferred (client, next TestFlight)

- `store.lastError` is written ~30 places, rendered nowhere; interrupt/send
  failures are invisible on the phone. Needs a small error surface.
