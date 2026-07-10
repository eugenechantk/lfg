# Improvement Log Digest — 2026-07-10

**Logs processed:** 44 files (2 prior digests, 31 substantive logs, 11 empty/near-empty templates)
**Date range:** 2026-06-29 → 2026-07-10
**Note:** the 6/29 digest claimed its logs were deleted, but several 6/29 files still existed (Syncthing resurrection or post-digest creation); their content was re-captured here.

## Patterns (recurring across 2+ sessions)

### P1. Reasoning from a proxy; no disconfirmation before declaring root cause — FAILED FIX, top priority
- **Frequency:** 6+ sessions (07-01 ×3, 07-09 ×4, 07-10 ×2)
- **Summary:** verified the answered state when the bug was the pending state; diagnosed VPN from CLI-process routing when the network extension bypasses it (disconfirming fact was in the first command's output); Air→phone ping when the symptom was phone→Air; 6h of TestFlight theories without comparing version trains; "correctly excluded" claimed from code-reading, disproven by one grep; ~6 hypotheses before dumping a predicate's two inputs.
- **Current coverage:** memories `ground-truth-before-hypothesizing` + `disconfirm-before-declaring-root-cause` exist and were repeatedly violated.
- **Fix applied:** both memories sharpened — measure the subject not a proxy; benign-explanation-first; re-read first commands for refutation; sentinel-returning probes are broken tools; predicate wrong → dump inputs; diagnosis docs label claims verified vs inferred; resolve identities from ps/pidfiles; `git log --grep` prior art; poll-for-absence after kills.

### P2. Tool success banner ≠ outcome (deploy layer)
- **Frequency:** 5 sessions. "Successfully uploaded" ≠ build visible; "done" with 14 commits unpushed and the second host never probed; stale serves silently kept ports.
- **Coverage:** TestFlight half fixed in skill (DoD + downgrade guard, ✅). Remaining gap fixed via project CLAUDE.md: multi-host DoD = push + probe the other host; kill by PORT and verify the NEW code answers.

### P3. xcode-select on CommandLineTools blocks FlowDeck UI — FAILED FIX (recurred after memory existed)
- **Fix applied:** memory `flowdeck-ui-needs-real-xcode-select` sharpened — check `xcode-select -p` in the FIRST command of any iOS visual-verification task; request the sudo line up front; DEVELOPER_DIR scope table.

### P4. FlowDeck sim-guard + CLI gotchas — FAILED FIX (under-specified memory)
- **Fix applied:** memory `flowdeck-sim-guard-cwd` sharpened — guard name derives from cwd BASENAME; no `cd` in ANY bash command; `--simulator` not `--destination`; `ui type` positional; guard-rotation recovery.

### P5. Simulator state-seeding trap (cfprefsd) — FAILED FIX (project CLAUDE.md note was misleading)
- **Fix applied:** project CLAUDE.md iOS section corrected — full recipe: terminate app → plistlib write → kill cfprefsd → `simctl launch` (not `flowdeck run`, which reinstalls); plus notification-prompt ghost, raw HID for toolbar taps, pinch→double-tap, `--level info`, simctl-push can't background-wake, .ips-first, no nav mutation in launch transaction.

### P6. Coordinate clicks/typing fail on Apple UI; accessibility tree works first try
- **Frequency:** 4 sessions (incl. cliclick DENYING a TCC dialog — poisoned TCC.db; cliclick can't fire SwiftUI List buttons, AXPress works).
- **Fix applied:** new macOS-automation section in project CLAUDE.md: AX-first, never coordinates on security dialogs, System Events keystroke, activate-then-click, osascript subprocess not NSAppleScript, stable codesign identity for TCC.

### P7. Session-start checklist skipped / improvement log created late (3 sessions)
- **Fix applied:** SessionStart hook in `~/.claude/settings.json` auto-creates the session improvement log when `improvement-log/` exists in the project — instruction-based enforcement demonstrably failed.

### P8. Concurrent lfg sessions share test rigs and deploy trees, not just files
- **Fix applied:** project CLAUDE.md concurrent-sessions hazard extended (sims/worktrees/scratch servers; archive from a snapshot).

### P9. Machine identity is not session-constant on lfg
- **Fix applied:** project CLAUDE.md hazards — re-verify `hostname` before machine-state ops; stale pids/sims/paths after migration; second exec path before restarting a remote host's server; no bare setInterval fan-out on the single loop; Bun auto-loads `.env`; codex-in-pane nulls `tmuxTarget` (send 409s).

### P10. Never guess a JSON/selector shape — print one record first
- **Fix applied:** new memory `probe-shape-before-scripting`.

### P11. Over-asking at non-forks ("(Recommended)" tell)
- **Fix applied:** global CLAUDE.md one-liner — if you can write "(Recommended)" with a rationale, implement it and state the decision; plus: after compaction, re-check Codex routing before resuming implementation.

## One-offs persisted
- brew: Claude Code cask is `claude-code@latest`; corrupt jws.json → clear `$(brew --cache)/api` (new memory).
- TestFlight host discriminator: `rbenv versions` shows only `system` → secondary host (both memories updated).
- Viewport-not-fullPage screenshot verification for landing pages (memory note).

## Not persisted (rationale in analysis)
zsh `=name` expansion trivia; pmset filtering; elapsed-time misreads; per-instance product bugs (`/api/sessions` dupes/latency, fork-twin, supervisor liveness probe) → product backlog, tracked in their sessions' diagnosis docs.

## Already addressed (verified in logs)
TestFlight DoD + downgrade guard; sendq bracketed-paste + transcript-confirm; rbenv/secondary-host memories; `/api/file` tmp roots + Range/206; listview500 3-layer fix; APNs topic + a11y-label taps.

## Logs deleted in this consolidation
All logs 2026-06-29 → 2026-07-09 except `improvement-log-20260709-081259.md` (modified today — treated as live). Kept: both prior digests, all 2026-07-10 files.
