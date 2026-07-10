# Improvement Log — Session 20260710-missing-sessions

## Tracker

- [ ] 2026-07-10 — Diagnosis claimed sync-conflict files were "correctly excluded" from code-reading alone; live testing proved the opposite
- [ ] 2026-07-10 — Spent ~6 tool calls on cliclick coordinate clicks that never fire SwiftUI List row buttons; AXPress worked first try
- [ ] 2026-07-10 — First Codex status monitor parsed `--json` output wrong and misreported the job as gone

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
