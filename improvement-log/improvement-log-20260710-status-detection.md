# Improvement Log — Session 20260710-status-detection

## Tracker

- [ ] 2026-07-10 — Background watcher script died on zsh read-only variable `status`
- [ ] 2026-07-10 — SC2 probe watched the wrong job: assumed `jobs[]` was oldest-first without eyeballing the real record
- [ ] 2026-07-10 — First SC2 delegation (spark) finished in 10s, before the observation window even opened
- [ ] 2026-07-10 — `lsof -ti :8766` without `-sTCP:LISTEN` killed a random connected process instead of the server
- [ ] 2026-07-10 — Repeated flowdeck `scroll --direction up --distance 0.9` pulled down the cover sheet / locked the sim repeatedly (cost ~10 min of recovery)

## Log

### 2026-07-10 — Background watcher script died on zsh read-only variable `status`

**What happened:** A background polling loop used `status=$(...)` as a variable name; zsh reserves `status` as a read-only alias for `$?`, so the script exited immediately with "read-only variable: status" and the supervision gap went unnoticed until the failure notification.
**Why this was wrong:** Wasted a round-trip relaunching the watcher. This shell is zsh (stated in the environment info), and `status`/`path`/`argv` are classic zsh reserved variables.
**What better looks like:** In zsh shell snippets, never use `status`, `path`, `argv`, or `options` as variable names — prefix locals (e.g. `jstatus`).

### 2026-07-10 — SC2 probe watched the wrong job (jobs[] order assumption)

**What happened:** The probe selected `js[js.length-1]` assuming the codex plugin's `jobs[]` array was oldest-first. It's newest-first, so the probe tracked an already-completed job for its entire 5-minute run and produced a useless log; the whole probe + delegation cycle had to be redone.
**Why this was wrong:** This is exactly the [[probe-shape-before-scripting]] memory — I had the real `state.json` in context from an earlier turn (where the newest job printed first) and still scripted against an assumed shape.
**What better looks like:** Before parsing any record programmatically, re-check ordering/shape against the actual data already in hand — one `node -e` eyeball costs seconds; a wrong-shape probe costs a full observation cycle.

### 2026-07-10 — First SC2 delegation too fast for the observation window

**What happened:** Used the spark model for the probe delegation to be cheap; the job completed in 10 seconds — before my turn had even ended — so there was no pane-idle-while-job-running overlap to observe.
**Why this was wrong:** The probe's subject must outlive the observation setup. I optimized for cost on the thing whose duration WAS the experiment.
**What better looks like:** When a live probe needs a temporal overlap, size the workload for the window first (default model, meatier task), cost second — one wasted cycle costs more than the model delta.

### 2026-07-10 — lsof kill without -sTCP:LISTEN hit the wrong process

**What happened:** Restarting the serve process with `kill $(lsof -ti :8766 | head -1)` killed an unidentified process that merely had an ESTABLISHED connection to port 8766 — `lsof -ti :port` lists clients too, and `head -1` picked one. The server kept running (flag not loaded); a second, correct kill was needed, and the collateral victim is unidentifiable after the fact.
**Why this was wrong:** The project CLAUDE.md even says "kill by PORT" — but the safe form is listener-only. Killing an unknown pid on a busy multi-session host is exactly the class of collateral the concurrent-sessions hazard warns about.
**What better looks like:** Always `lsof -nP -iTCP:<port> -sTCP:LISTEN -t`, echo the pid and its command line BEFORE killing, then kill. Never `head -1` an unfiltered lsof.

### 2026-07-10 — flowdeck full-height up-scrolls derail the simulator

**What happened:** To scroll a long list to the top I fired repeated `scroll --direction up --distance 0.9`. The gesture's start point reaches the top screen edge, which iOS interprets as a cover-sheet pull — the sim ended up on the lock screen twice and once in the wallpaper-customize editor; recovery burned ~10 minutes mid-test.
**Why this was wrong:** Distance 0.9 makes the drag span the whole screen including system-gesture zones. The efficient alternative existed the whole time: `scroll --until "label:…" --direction up` targets an element directly and stops.
**What better looks like:** Keep flowdeck scroll distances ≤0.5, prefer `scroll --until` with a target label over blind repeated scrolls, and never start gestures within ~80pt of the top/bottom edges. (Silver lining: the accidental lock screens produced the Live Activity evidence.)
