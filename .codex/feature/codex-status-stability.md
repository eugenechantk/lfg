# Feature: Stable Codex Session Status

## User Story

As an LFG user monitoring Codex sessions, I want each session to remain Running for its real turn and Idle after completion so that rows do not jump between status groups while nothing changed.

## User Flow

1. Open or resume a promptless Codex TUI, including one that has switched between several conversations.
2. Start a Codex turn.
3. LFG binds the live process to a rollout the process actually has open.
4. Polling and journal updates keep the session Running until the rollout records a real completion or abort.

## Success Criteria

- [x] SC1: A promptless Codex process with multiple historical rollout files binds to the freshest rollout it actually has open, not a nearby rollout inferred from process launch time. — **Verify by:** `src/codex-bind.test.ts` regression fixture.
- [x] SC2: Batched process inspection maps open Codex rollout paths to the correct PID without leaking paths across processes. — **Verify by:** `src/procinfo-codex.test.ts` parser tests.
- [x] SC3: Existing prompt, resume, fork, and turn-state behavior remains green. — **Verify by:** focused Bun suites and full `bun test`.
- [x] SC4: A live Codex turn produces no false idle edge across repeated REST and journal samples. — **Verify by:** runtime API/journal probe and independent verification audit.

## Platform & Stack

- **Platform:** macOS/Linux backend consumed by iOS and macOS clients
- **Language:** TypeScript on Bun
- **Key frameworks:** Bun test, tmux, `ps`/`lsof` process discovery

## Steps to Verify

1. Run the focused Codex binding, process inspection, turn-state, and session-state suites.
2. Run the full Bun suite and TypeScript type-check.
3. Sample a live Codex turn through `/api/sessions` and `/api/events/page`; confirm no false `busy: false` edge.
4. Run an independent verification audit against these criteria.

## Implementation Phases

### Phase 1: Reproduce and pin the binding failure

- Scope: add pure regression coverage for batched open-file parsing and open-rollout selection.
- Success criteria covered: SC1, SC2.
- Verification gate: new tests fail before implementation and pass afterward.

### Phase 2: Use open rollouts during enumeration

- Scope: batch-inspect Codex PIDs once per scan and prefer an owned rollout before launch-time fallback.
- Success criteria covered: SC1, SC3, SC4.
- Verification gate: focused/full tests, type-check, and live sampling.

## Decision Log

- Use the rollout files opened by the Codex process as the ownership signal. Process launch proximity is only a fallback: Codex can delay rollout creation and a long-lived TUI can switch conversations without restarting.
- When a process owns several open rollouts, prefer the freshest owned rollout. Codex retains older file descriptors after in-TUI switches, while the active conversation continues advancing.
- Keep process inspection batched so the fix adds one host-level probe, not one `lsof` process per session.

## Verification Evidence

- Red phase: the new binding/parser suites failed because `pickOpenCodexThread` and `parseOpenCodexRollouts` did not exist.
- Focused binding/parser suites: 23 passed, 0 failed.
- Focused binding + turn/session-state suites: 80 passed, 0 failed.
- Type-check: `bunx tsc --noEmit` passed.
- Full suite: 685 passed, 0 failed across 60 files.
- Live host after reload: the known flapping pane `codexy-182018-81515` resolved to its actual open rollout `01a023d5-f1b4-7070-9ad2-cce97ea467e4`, not stale rollout `01a023d5-b48b-7260-9e82-9c219e9b67d8`.
- Live stability sample: 10 repeated REST scans kept that pane on `f1b4` and idle, kept the active verification turn running, and emitted no relevant journal edge from sequence 455997 through 456002.
- Independent audit: PASS. Report: `.claude/evidence/20260822-033045-verification-audit/evidence.md`.

## Bugs

- Fixed: one real Codex turn emitted 95 alternating busy edges because a long-lived promptless TUI was bound to the wrong rollout.
