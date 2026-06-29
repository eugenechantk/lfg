# Improvement Log — Session 20260629-pending-pickup

## Tracker

- [ ] 2026-06-29 — Initially mis-targeted the aisdk backend; user's sessions are mostly raw-claude tmux (sendq.ts path)
- [ ] 2026-06-29 — No observability on the sendq deliver() seam — can't see why a send fails without catching it live
- [x] 2026-06-29 — ROOT CAUSE CONFIRMED via live capture: (1) multi-line sends submit early (send-keys -l sends literal \n = Enter); (2) confirmation gated on brittle composer scrape that fails when busy. See .claude/diagnosis-pending-pickup.md

## Log

### 2026-06-29 — Mis-targeted aisdk backend first

**What happened:** Spawned an Explore agent that emphasized the aisdk command-file path and spawnSync-hang theory. The live host actually runs 23 raw `/claude` procs vs 6 aisdk — the dominant send path is `sendq.ts` (tmux send-keys + screen-scrape confirm), which the user confirmed.
**Why this matters:** Wasted a step theorizing about the wrong delivery backend. Should have checked `ps` for which backend dominates before forming hypotheses.
**What better looks like:** For a delivery bug, enumerate which backend the user's sessions actually use (one `ps`) before mapping the pipeline.

### 2026-06-29 — Zero observability on deliver()

**What happened:** sendq.ts has no logging. The `failed` QueuedMsg carries an `error` string but it's in-memory and pruned, so by the time we look the queue is empty.
**Why this is wrong:** A bug that happens "often" should be trivially diagnosable from a log. It isn't.
**What better looks like:** deliver() should append failure reason + a pane snapshot to a log file. Pending fix.

### 2026-06-29 — Symptom (ground truth from user)

Stuck at pending → flips to failed → keeps failing on retry. Deterministic, not transient.
Most likely branch: `deliver()` only presses Enter after `boxHasNeedle()` confirms the typed
text via `inputBoxText()` screen-scrape; if the composer can't be parsed in the current TUI
state, it never submits → "message never left the input box after retries", identical on retry.
Two other failed branches possible: "session is not in a tmux pane" (target null) and
"a prompt/selector wouldn't dismiss — answer it first". Need the literal error to disambiguate.
