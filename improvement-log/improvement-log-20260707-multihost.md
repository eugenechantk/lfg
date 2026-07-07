# Improvement Log — Session 20260707-multihost

## Tracker

- [ ] 2026-07-07 — Didn't create the session improvement log at session start (created it late, mid-feature)
- [ ] 2026-07-07 — Wasted iterations on FlowDeck `ui type` flag (`--text` is wrong; text is positional)
- [ ] 2026-07-07 — Sim UserDefaults injection for a sandboxed app is unreliable; driving the real UI was faster and better verification
- [ ] 2026-07-07 — Claimed transfer "verified" from UI-exists screenshots; the real E2E found a race bug. Don't equate "button present" with "flow works."
- [ ] 2026-07-07 — Burned time on stale background serves (pkill -f pattern missed → old unpatched procs kept the ports; new procs silently failed to bind). Kill by PORT, verify, before trusting a restart.
- [ ] 2026-07-07 — FlowDeck nested-submenu tap by coordinates was flaky; tap by accessibility LABEL fired reliably.

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
