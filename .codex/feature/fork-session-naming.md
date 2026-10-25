# Feature: Fork session naming

## User Story

Forked sessions need a useful initial name and the same automatic renaming as
other sessions.

## User Flow

1. Choose Fork session on a Claude or Codex conversation.
2. The branch starts with `Fork of <source title>`.
3. Autopilot examines the branch through its existing retitle step.
4. A manual rename pins only the branch's name.

## Success Criteria

- [x] SC1: Bound Claude, managed Codex, and external Codex forks receive an initial
  title. Verify with naming tests and an isolated fork API probe.
- [x] SC2: Initial names use automatic provenance and remain eligible for the
  existing retitler. Verify with a retitle lifecycle probe using a stub model.
- [x] SC3: Source titles and manual branch names remain intact. Verify with
  regression tests and the lifecycle probe.
- [x] SC4: A Claude branch that binds after the response receives its name on
  discovery. Verify with an isolated delayed-binding discovery probe.
- [x] SC5: A failed title write preserves the fork response and session list.
  Verify with an isolated corrupt-title-store probe.

## Platform and Stack

Bun host, TypeScript. All clients use the same fork endpoint.

## Implementation Phases

One phase: seed automatic fork titles, handle delayed discovery, test the existing
retitle lifecycle, and run an independent audit.

## Decision Log

- Use the source's display title with a `Fork of` prefix. Do not inherit the
  source's human-title provenance: the user did not manually name the branch.
- Preserve the retitler's existing cadence, minimum turns, growth threshold, and
  topic-drift policy.
- Keep the production host running. Verify through isolated state and fixtures.
- Keep strict title writes. Catch failures at discovery and the fork route so a
  damaged title file cannot hide sessions or invite duplicate forks.

## Verification Evidence

- Before implementation, five new naming cases failed because the seed helper
  did not exist. Evidence: `fork-session-naming-red.txt` beside this document.
- Final focused run: 159 tests passed across 11 files. This covers title writes,
  autopilot, fork HTTP history, managed records, and idle lifecycle regressions.
  Evidence: `fork-session-naming-tests-final.txt`.
- `bunx tsc --noEmit` passed. `git diff --check` passed.
- Real managed Codex fork: HTTP 200, `Fork of Fork naming smoke` visible through
  REST, title provenance `auto`, and `busy: false`. The source transcript hash
  stayed unchanged. The disposable branch closed successfully. The check passed
  again after adding title-error handling.
  Evidence: `.codex/evidence/fork-session-naming/runtime/result.json`.
- Independent audit: PASS for SC1 through SC5. The auditor exercised actual
  discovery, the common fork route with provider launches stubbed, and actual
  `runRetitle` with a stub model. Renaming persisted, checkpoints prevented a
  repeat model call, and manual branch names stayed pinned. Corrupt title data
  stayed intact; discovery and the fork response survived and retried after repair.
  The auditor also passed 106 focused tests and TypeScript checking.
  Report: `.codex/evidence/fork-session-naming/audit/REPORT.md`.
- Full repository run: 1,296 passed, six failed. Two iOS source assertions also
  failed against unchanged HEAD files. Four search/resumable cases exceeded the
  default five-second limit. Separate runs with a 20-second limit passed all 22
  search cases and all three resumable cases. Evidence: the full-suite,
  ios-baseline, search-recheck, and closed-recheck logs beside this document.

## Release and Limits

- Host-only change. No iOS or desktop client changes are required.
- Production Pro and Air hosts now run the fix after the authorized restart
  below. Nothing was committed or pushed.
- Real Claude and external Codex launches were not repeated. The independent
  audit stubbed those provider outcomes at the shared route.
- The audit used a stub model to verify the existing retitle sequence. It did
  not wait for a production autopilot tick or request a real title-model answer.
- Existing autopilot code checks manual provenance before its model call. A
  concurrent manual rename during that call remains outside this change.

## Host restart: 18 October 2026

- The user requested both host restarts. Verified direct SSH access to the Air,
  no active phone sign-ins, and the existing supervisors before restarting.
- The Air was missing this patch. Saved its original files, applied only this
  task's patch, and verified both changed source files match the Pro exactly.
  Preserved unrelated Air working-tree edits. Its frozen dependency check and
  TypeScript check passed.
- Restarted only each port-8766 listener under its existing supervisor. Pro PID
  changed from 74480 to 5254; Air PID changed from 833 to 1227.
- Both fresh processes returned the expected host identity and session list.
  Pro returned 45 sessions; Air returned two. The Pro's original tmux panes
  remained present. The Air had no tmux panes before its restart.
- The Pro's live list showed three automatically named managed forks. The Air
  had no live managed forks; its exact code hashes and fresh process were verified.
- Evidence: `.codex/evidence/fork-session-naming/restart-*-before.json`,
  `restart-*-after.json`, and `restart-*-live.json`. Air file backups and the
  applied patch are in the same evidence folder.

## Bugs

_None yet._
