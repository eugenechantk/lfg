# Feature: Codex stays running during silence

## User Story

As an LFG user, I want quiet Codex turns to remain Running until they finish or stop.

## User Flow

1. Start a Codex turn.
2. Codex waits, thinks, or runs a tool without writing output.
3. LFG keeps the session Running.
4. Completion or an abort changes the session to Idle.

## Success Criteria

- [x] SC1: An explicit open Codex turn survives silence beyond 15 minutes. **Verify by:** session-state regression tests with old transcript timestamps.
- [x] SC2: Codex without a terminal pane uses turn records in REST, the journal, and push observations. **Verify by:** bare-session and push regression tests, plus a runtime journal probe.
- [x] SC3: Completion, errors, aborts, and confirmed stops still clear Running. **Verify by:** lifecycle and interrupt tests.
- [x] SC4: Claude stall handling and vanished-session retractions still work. **Verify by:** existing session-state and journal-pump tests.
- [x] SC5: The running host uses the fix. **Verify by:** host reload, REST/journal samples, and independent audit.

## Platform & Stack

TypeScript backend on Bun. iOS and macOS clients consume its status.

## Steps to Verify

1. Run focused turn-state, session-state, journal, push, and interrupt tests.
2. Run the full Bun suite and TypeScript checks.
3. Reload the host and compare REST with journal status.
4. Run the independent verification auditor.

## Implementation Phases

1. Reproduce the timeout with regression tests.
2. Preserve explicit lifecycle evidence and use it for Codex without a pane.
3. Verify tests and the running host.

## Decision Log

- Treat Codex's paired lifecycle records as authoritative during silence. Process enumeration and disappearance retractions handle ownership loss.
- An explicit open turn also supports a newer hook that agrees it is running. Newer idle or ended hooks still close the turn.
- Keep Claude's existing stall guard. Its inferred open turns can lack a closing record.
- Fix backend status derivation. Client polling must agree with the journal.

## Verification Evidence

- Regression before the fix: five quiet-Codex cases failed because the resolver returned `idle` with `stalled: true`.
- Focused suites after the audit correction: 172 tests passed across seven files, including push delivery tests. Covers silence, hook ordering, completion, errors, aborts, confirmed stops, Claude stalls, and disappearance retractions. Output: `.codex/evidence/codex-quiet-running-status/focused-tests.log`.
- `bunx tsc --noEmit`: passed. Output: `.codex/evidence/codex-quiet-running-status/typecheck.log`.
- Full suite after the audit correction: 1,170 passed; one existing binary-resolution test failed. It selects the installed `/opt/homebrew/bin/codex` over its fake PATH fixture. The same failure reproduces in the untouched binary suite alone. Logs: `bun-test.log` and `baseline-codex-bin.log` in the evidence directory.
- Runtime probe: PASS. Two disposable processes held writable rollouts with timestamps aged two hours. Real process discovery, three snapshots, journal polling, and push observations kept both Running without file growth. Completion, abort, new starts, and ownership-loss retractions passed. Artifact: `.codex/evidence/codex-quiet-running-status/runtime-probe.json`.
- Reloaded the local host: listener changed from PID 41175 to 45361. `/api/ping` returned `ok: true`.
- Live host samples: four REST snapshots kept this active session busy. The journal contained a matching `busy: true` event and no false idle event. Artifact: `.codex/evidence/codex-quiet-running-status/live-after.json`.
- Final independent audit: PASS. A separate agent reran 172 focused tests, typecheck, the hook probe, and an expanded runtime probe. It verified completion, aborts, errors, confirmed stops, new starts, and ownership loss across REST, journal, and push. Report: `.codex/evidence/codex-quiet-running-status/audit/report.md`.
- The first independent audit found an agreeing-hook edge case: a newer running hook still timed out an explicit open Codex turn. The new regression failed before the correction. Added tests also preserve newer idle/ended hooks and later stalled hooks after a completed turn.
- After the correction, the auditor's original hook probe passed through the resolver, journal, and push observer. Artifact: `.codex/evidence/codex-quiet-running-status/hook-regression-after.json`.
- Repeated the full runtime lifecycle probe after the hook correction: PASS.
- Final host reload: PID 45361 changed to 62533. Four REST samples and the live journal agreed that the active session was busy. Artifact: `.codex/evidence/codex-quiet-running-status/live-after-final.json`. The auditor independently confirmed the final listener and three additional live samples.

## Bugs

- Fixed: the shared 15-minute stall guard demoted explicit Codex starts.
- Fixed: the journal used a four-second freshness window when a Codex session had no terminal pane.
- Fixed: Codex REST skipped turn records for CLI processes without a terminal pane.
- Fixed: push observations treated Codex sessions without a terminal pane as idle.

## Residual Risks

- An owner that stays alive after a crash and writes no terminal event can retain an open Codex turn. Silence alone cannot distinguish it from real work.
- The unrelated binary-resolution test needs separate isolation from the installed Codex executable.
