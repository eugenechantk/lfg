# Improvement Log — Session 20260710-missing-sessions

## Tracker

- [ ] 2026-07-10 — Diagnosis claimed sync-conflict files were "correctly excluded" from code-reading alone; live testing proved the opposite
- [ ] 2026-07-10 — Spent ~6 tool calls on cliclick coordinate clicks that never fire SwiftUI List row buttons; AXPress worked first try
- [ ] 2026-07-10 — First Codex status monitor parsed `--json` output wrong and misreported the job as gone
- [x] 2026-07-10 — Background Ruby ASC poller ran 17 min with zero output (no $stdout.sync); Eugene had to nudge — FIXED: `verify_testflight_build` DoD lane added to testflight-deploy skill (synced to all apps, verified green on build 202607101926); spaceship filter gotcha documented; unbuffered-background-output rule added to global CLAUDE.md

## Log (addendum)

### 2026-07-10 — Background poller silent for 17 minutes

**What happened:** The ASC definition-of-done poller ran as a background task with buffered stdout (Ruby buffers when stdout isn't a tty), so its output file stayed at 0 bytes for 17 minutes and Eugene had to ask what was happening. A separate spaceship quirk compounded it: `Build.all(version: ...)` filtering returned nothing for a build that the unfiltered list showed as VALID.
**Why this was wrong:** A long-running background probe that emits nothing is indistinguishable from a hung one — the whole point of the log file is observability. And the version-filter quirk is exactly the class of "query by filter, not sorted listings" trap the testflight skill warns about, but inverted (here the FILTER lied and the listing was right).
**What better looks like:** `$stdout.sync = true` (or stdbuf/PYTHONUNBUFFERED equivalents) in every backgrounded script, and prefer short foreground one-shot probes repeated on wake over one long silent loop. For spaceship: fetch the unfiltered build list and select client-side; trust no server-side filter until verified once (see [[probe-shape-before-scripting]]).

## Log

### 2026-07-10 — "Correctly excluded" claim made without testing

**What happened:** The missing-sessions diagnosis asserted Syncthing `.sync-conflict` transcript copies were "correctly excluded by the UUID filter" based on reading `UUID.test(id)` in the code. During implementation verification, the pagination walk showed those 6 files WERE returned — the regex is unanchored, so a filename containing a UUID substring passes.
**Why this was wrong:** A claim about filter behavior was stated as verified when it was only inferred. The disconfirming check (grep the endpoint output for `sync-conflict`) took one command and would have caught it at diagnosis time.
**What better looks like:** In a diagnosis, separate "verified" claims from "inferred from code" claims, and run the one-command empirical check for anything declared "not the cause" (see memory [[disconfirm-before-declaring-root-cause]]).

### 2026-07-10 — cliclick coordinate clicks don't fire SwiftUI List row buttons

**What happened:** Verifying the desktop app's click-to-resume, several `cliclick c:x,y` clicks on a List row (correct coordinates, window frontmost) did nothing, while the same tool clicked a toolbar segmented control fine. `AXPress` on the row's AXButton via System Events fired the action immediately.
**Why this was slow:** ~6 rounds of click/screenshot/theorize (including a TCC detour) before switching approach.
**What better looks like:** For macOS SwiftUI app automation, go straight to the accessibility tree (System Events → AXPress on the target element). Coordinate clicks are the fallback, not the default. Worth folding into a macOS-automation skill note if this recurs.

### 2026-07-10 — Codex job monitor misparsed status JSON

**What happened:** The background poll loop piped `codex-companion.mjs status <id> --json` through a python one-liner expecting `{status: ...}`; it printed `?` and exited, and a follow-up `result` call reported "no job found", briefly suggesting the run had died. Plain-text `status` showed it running fine.
**Why this was wrong:** Assumed the JSON shape instead of inspecting it once before writing the loop.
**What better looks like:** Before scripting against a tool's `--json` output, run it once and look at the actual shape; or parse the human-readable output defensively (which the second monitor did, successfully).
