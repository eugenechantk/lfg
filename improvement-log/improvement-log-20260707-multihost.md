# Improvement Log — Session 20260707-multihost

## Tracker

- [ ] 2026-07-10 — Declared gate G1 FAILED on an invalid rig: lsof -ti:PORT SIGSTOPped BOTH connection ends, freezing the app under test
- [ ] 2026-07-10 — Codex verified Swift with `swiftc -parse`, which misses actor-isolation errors (deinit touching @MainActor state)
- [ ] 2026-07-10 — Sim app-config plist edits clobbered by cfprefsd twice; simctl defaults write hit wrong domain
- [ ] 2026-07-10 — My D2 brief specified env strings that contradicted the house convention; caught only at live verify
- [ ] 2026-07-10 — Sat passively 'blocked on twin idle' for 3h; twin was already dead. Eugene had to prod.
- [ ] 2026-07-10 — Repo-local broken codex shim shadowed the Homebrew binary; first delegation spawn failed
- [ ] 2026-07-07 — Didn't create the session improvement log at session start (created it late, mid-feature)
- [ ] 2026-07-07 — Wasted iterations on FlowDeck `ui type` flag (`--text` is wrong; text is positional)
- [ ] 2026-07-07 — Sim UserDefaults injection for a sandboxed app is unreliable; driving the real UI was faster and better verification
- [ ] 2026-07-07 — Claimed transfer "verified" from UI-exists screenshots; the real E2E found a race bug. Don't equate "button present" with "flow works."
- [ ] 2026-07-07 — Burned time on stale background serves (pkill -f pattern missed → old unpatched procs kept the ports; new procs silently failed to bind). Kill by PORT, verify, before trusting a restart.
- [ ] 2026-07-07 — FlowDeck nested-submenu tap by coordinates was flaky; tap by accessibility LABEL fired reliably.
- [ ] 2026-07-07 — Long two-machine debug: guessed wrong causes 3× (TMUX-in-tmux, PATH, procStart) before isolating the real one (missing pidfile from synced ~/.claude/sessions). Should have gone straight to observing serve internals.
- [ ] 2026-07-07 — Multi-host hazard: syncing ~/.claude/sessions/ collides pid-keyed files across machines → sessions non-authoritative → no tmux target → sends fail. Fix: /sessions in .stignore. (→ memory)

## Log

### 2026-07-07 — Didn't create the session improvement log at session start

**What happened:** The Session Start Checklist requires creating `improvement-log/improvement-log-<id>.md` on the first message. I only created it near the end of a long multi-host feature build.
**Why this was wrong:** The log is meant to be a running journal written as observations happen, not reconstructed at the end. Batching loses detail and defeats the purpose.
**What better looks like:** First action of any top-level session (after git pull): create the improvement log. Then append in real time.

### 2026-07-07 — FlowDeck `ui type` flag confusion

**What happened:** Used `flowdeck ui simulator type --text "…"`; the command silently printed help (it takes the text as a positional arg: `type "…"`). Cost ~2 iterations mid-verification.
**Why this was slow:** Assumed a `--text` flag by analogy instead of checking `--help` first.
**What better looks like:** For an unfamiliar FlowDeck subcommand, run `--help` once before scripting a multi-step UI sequence around it.

### 2026-07-07 — Simulator UserDefaults injection for a sandboxed app

**What happened:** To seed a two-host config I tried (a) `xcrun simctl spawn <udid> defaults write <bundleid> …` — writes the sim's GLOBAL prefs domain, not the app's sandbox container, so the app never sees it; and (b) direct `defaults write <container>/…/<bundleid>.plist` — gets clobbered by the sim's `cfprefsd` cache (which runs on the host under CoreSimulator, so guest `killall cfprefsd` doesn't reset it). Both failed. Driving the real UI (ConnectView → type URL → Save; Settings → Add host) worked immediately and is stronger evidence per `verify-ui-by-tapping`.
**Why this matters:** The ios/CLAUDE.md plist-injection trap note is for setting a URL in a *text field* to avoid automation flakiness, but for a **sandboxed app's UserDefaults** the plist-write route is unreliable. The real-UI route both worked and satisfied the "exercise the real seam" rule.
**What better looks like:** To seed iOS app state in the sim, prefer driving the real onboarding UI. Only reach for plist injection when there's no UI path, and if so, write the app *container* plist AND force `cfprefsd` to reload (or launch with a first-run so the daemon has no stale cache). Candidate to persist as a memory once confirmed twice.

### 2026-07-07 — "Verified" from screenshots ≠ E2E; the real test found a bug

**What happened:** In the previous turn I marked the transfer SC as "verified (UI)" from screenshots showing the "Move to host" menu item, and deferred the real transfer to "Eugene's two machines." When Eugene asked to actually E2E test it in the sim, I stood up two local `lfg serve` instances (isolated data dirs, shared `~/.claude`) and drove a real transfer — which **failed**, exposing a genuine close→resume race (resume dedupes against the still-dying source process and no-ops, leaving the session dead). Fixed with an `alreadyLive`-retry loop; re-verified end-to-end (session moved A→B, history intact, post-transfer send routed to B).
**Why this matters:** A present button is not a working flow. The screenshot gave false confidence; only exercising the real seam surfaced the bug. This is exactly the `verify-real-seam-not-mocks` rule — and I should have run the two-serve E2E myself rather than deferring it.
**What better looks like:** For any orchestration/multi-step action (especially cross-service), exercise the real runtime path at least once before calling it verified — even if it means standing up a local multi-instance harness. "Needs the user's hardware" is sometimes true, but check first whether a local harness can exercise the same seam.

### 2026-07-07 — Stale background serves silently kept ports

**What happened:** Restarted the two test serves after patching them; the new processes didn't take effect because `pkill -f 'lfg-hostA/src/cli.ts'` didn't match (path/pattern), so the old unpatched serves kept the ports and the new `bun run` silently failed to bind and exited. Spent time confused why a code patch "wasn't running."
**What better looks like:** After restarting a port-bound service, verify the NEW code is live (a cheap probe — here a request-log line) before trusting it. Kill by PORT (`lsof -ti:PORT | xargs kill -9`), not by a fuzzy process-name pattern.

### 2026-07-10 — Passive blocking on the twin session (Eugene had to prod)

**What happened:** Tasks C and D2 were queued behind "twin session goes idle." I checked once, reported "blocked," and stopped. The twin had actually died mid-Task-C ~3 hours earlier (green build, then silence, gone from the sessions list). Eugene had to ask "why are you not working on C and D2?" before I re-checked and took over.
**Why this was wrong:** "Blocked on external state" is not a terminal state — it's a state to poll. The evidence for the block (twin active) had a 3-hour-old timestamp I never refreshed. One `curl` would have unblocked half a day of work.
**What better looks like:** When work is gated on an external condition (another session, CI, a lock), schedule an active re-check (Monitor/ScheduleWakeup or a periodic curl) at creation time, and record WHEN the blocking evidence was observed. Stale evidence = re-verify before continuing to wait.

### 2026-07-10 — Broken repo-local codex shim shadowed Homebrew binary

**What happened:** `codex exec` failed with ENOENT: `node_modules/.bin/codex` in the main lfg repo points at a missing vendored binary (`@openai/codex-darwin-arm64/vendor/.../codex`) and PATH-shadows `/opt/homebrew/bin/codex`, which works.
**What better looks like:** Invoke `/opt/homebrew/bin/codex` explicitly from lfg worktrees, or fix the repo install (`pnpm install` to restore the vendored binary / remove the dep). Worth fixing the root cause so future sessions don't trip.

### 2026-07-10 — Sim preference edits: cfprefsd clobbered two rounds of host-config writes

**What happened:** Pointing the sim app at a scratch server took 4 attempts: (1) direct container-plist write — clobbered by the app re-saving its cfprefsd-cached list; (2)+(3) `simctl spawn defaults write` — writes the sim USER domain, not the app container, so the app never saw it; (4) container plist + `kill -9` the sim's cfprefsd (the CoreSimulator one in `ps ax`) — worked. Separately, the same-machine scratch server inherited prod's `host-id` (data-dir migration copies it), so the app's hostId dedupe silently collapsed my second host until I wrote a fresh uuid.
**Why this was slow:** The existing ios/CLAUDE.md trap note ("write the plist and relaunch") is incomplete — it omits cfprefsd. And I debugged the app's "clobbering" behavior before checking WHERE simctl defaults writes.
**What better looks like:** Recipe is now in `.claude/feature/phase2-background-continuity.md` (D2 results). Candidate for the ios/CLAUDE.md trap note during /self-improve: container plist + kill sim cfprefsd + fresh host-id for local scratch hosts.

### 2026-07-10 — Delegation brief contradicted house convention (env strings)

**What happened:** My D2 brief told Codex to send `env: "dev"/"prod"`; the server and the existing push registration both use `"sandbox"/"production"` (server treats anything != "production" as sandbox). Release builds would have silently registered as sandbox — production Live Activity pushes would all fail. Caught only because live verification surfaced `env: "sandbox"` where I expected `"dev"`.
**Why this was wrong:** I wrote the brief's env rule from memory instead of grepping the existing convention (`PushManager.apnsEnv`, `push-devices.json`) — 30 seconds of checking. Codex implemented the spec faithfully; the bug was the spec.
**What better looks like:** When a brief pins a cross-boundary contract (strings, field names, enums), quote the existing code's literal values in the brief, never paraphrase from memory. Live-verify contracts even when both halves are "done".

### 2026-07-10 — Invalid gate rig: lsof -ti:PORT hits both connection ends

**What happened:** To black-hole the scratch server I ran `lsof -ti:8797 | xargs kill -STOP`. That port query lists EVERY process with a socket on 8797 — including the LFG simulator app holding the client end of the SSE connection. The app froze; the "Connected" pill and timestamps were a freeze-frame; I declared gate G1 FAILED (100s, no flip) before noticing the app's process state was `Ts`. Cost: one full gate cycle + a false FAIL that nearly triggered a fix-hunt on correct code.
**Why this was wrong:** Frozen UI + frozen relative timestamps were the tell (a live SwiftUI list recomputes "10s ago" per render). I trusted the screenshot as app-state evidence without confirming the app process was actually running.
**What better looks like:** Target the LISTENING socket only: `lsof -ti TCP:PORT -s TCP:LISTEN`. And before declaring any watchdog/timer gate failed, `ps -o stat` the app process — a `T` state invalidates the run. Frozen relative timestamps in consecutive screenshots = suspect a suspended process, not a broken feature.

### 2026-07-10 — Codex sandbox verification gap: swiftc -parse misses concurrency errors

**What happened:** Codex (sandbox-blocked from flowdeck builds) verified its Swift with `swiftc -parse`, which passed — but the real build failed: a `deinit` touching @MainActor state is an actor-isolation error that only full type-checking catches.
**What better looks like:** Expect this class of miss whenever Codex reports parse-only verification for Swift 6 code; budget for one compile-fix round-trip, or have briefs suggest `swiftc -typecheck` with the right target/SDK flags when full builds are sandbox-blocked.
