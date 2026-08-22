# Improvement Log Digest — 2026-08-23

**Logs processed:** 5 (sessions 20260822-031302, -040344, -040357, -050000, -163042; three were empty templates)
**Date range:** 2026-08-22 (one day, the iPhone-client bug blitz)
**Observations found:** 20 (all unaddressed at time of writing; actions below)

## Patterns (recurring)

### 1. Instrument the decision point FIRST on state-machine bugs
- **Frequency:** 3 distinct bugs in one session (worker 040357: `isAtBottom` follow-latch, open-pin arrival check, tool-row windowStart walk) + prior sessions
- **Summary:** Gesture/pixel probes and inference repeatedly failed (3 failed probe designs, 2 shipped-then-retracted fixes); in every case 3-4 NSLog lines at the decision point answered it in one run. The one bug where instrumentation came FIRST (juking) was fixed in a single targeted attempt.
- **Root cause:** Habit of inferring internal state from external evidence; instrumentation treated as last resort instead of first move.
- **Current coverage:** memory [[ground-truth-before-hypothesizing]] exists but is framed around "get the error/read the source", not "log the state transition".
- **Recommended fix:** extend that memory with the instrument-first rule for state-machine/UI-movement bugs. **DONE** (memory updated).

### 2. Destructive file/git operations against a shared, uncommitted working tree
- **Frequency:** 3 incidents in one session (worker 040357): `git checkout --` destroyed another agent's uncommitted test work (recovered from a codex rollout); `Write` silently overwrote `TranscriptMerge.swift`; same Write-overwrite again minutes after logging the first.
- **Root cause:** "Restore to clean state" and "create new file" instincts assume a single-owner tree; this repo's normal state is N sessions' uncommitted WIP. The tool signal was even there ("File updated successfully" = existed) and went unread.
- **Current coverage:** repo CLAUDE.md has the concurrency hazard but says nothing about destructive ops; global CLAUDE.md says "look at the target before overwriting".
- **Recommended fix:** add an explicit hazard line to the repo CLAUDE.md: never `git checkout --`/`restore` a file that `git status` shows modified; check existence before `Write` to any unread path; codex rollouts/Claude transcripts are the undo log of last resort. **DONE** (CLAUDE.md updated).

### 3. Verification that skips a named condition hides the bigger defect
- **Frequency:** 2 in worker session (verified keyboard fix on an IDLE session when the report said "while live messages arrive" — the dropped condition carried the largest defect; stopped at one root cause when a second repro path existed), plus my own pre-written bug-010 evidence.
- **Current coverage:** [[verify-the-discriminating-case]], [[verify-real-seam-not-mocks]] — exist, didn't bite.
- **Recommended fix:** extend [[verify-the-discriminating-case]]: reproduce with EVERY condition the report names, together; a fix verified on one repro path is evidence about that path only. **DONE** (memory updated).

## One-off observations worth persisting

- **FlowDeck `type` emits `;` for `:`** (and coordinate-taps drift between keyboard planes) — silently corrupts URLs/ports; reported success. → new memory. **DONE**.
- Headless sim = no software keyboard → **already** memory `sim-keyboard-needs-simulator-app` (written same session).
- LazyVStack onAppear ≠ visibility → **already** memory.
- `lastError` cleared every refresh — check who CLEARS state before rendering it (lifetime is part of the contract). Captured here; no separate memory (repo-specific, now moot after the errorEvent redesign).
- A "safety net" predicate can swallow the case the real fix never covered; a flag's meaning is defined by every writer. Captured in bug-010/SC10 notes and [[verify-the-discriminating-case]] update.
- Mutating real host config to fake "offline" — existing memory [[lfg-stub-host-offline-repro]] covered this and wasn't applied; noted as a recall failure, no new entry.
- My session (050000): zsh eats unquoted bracket globs; `log` is shadowed → use `/usr/bin/log`; sandboxed `tailscale status` lies; never pre-write verification evidence; transport was diagnosed against deprecated Tailscale docs → memory `lfg-client-transport-is-cloudflare` **already written**, repo CLAUDE.md **already corrected**.

## Recommended actions

| # | Action | Mechanism | Status |
|---|--------|-----------|--------|
| 1 | Destructive-ops hazard (checkout --, Write-to-unread-path, rollout-as-undo-log) | repo `.claude/CLAUDE.md` | DONE |
| 2 | Instrument-first rule | memory `ground-truth-before-hypothesizing` | DONE |
| 3 | Every-named-condition rule | memory `verify-the-discriminating-case` | DONE |
| 4 | FlowDeck `type` punctuation trap | new memory `flowdeck-type-punctuation` | DONE |
| 5 | Historical backlog: ~190 tracked logs from Jul–Aug remain unconsolidated | run `/consolidate-improvement-logs` in a dedicated session | OPEN |

## Logs deleted after processing

All five 2026-08-22 logs (three empty; two fully captured above and in the memories/CLAUDE.md edits listed).
