# Improvement Log Digest — 2026-07-01

**Logs processed:** 9 (2026-06-30 → 2026-07-01; the 6/29 backlog was already covered by `consolidated-2026-06-29.md`)
**Observations found:** 11 (2 patterns, 4 one-offs worth persisting, 3 addressed, 2 empty logs)

## Patterns (recurring across 2+ sessions)

### 1. A previously-fixed bug that recurs is usually a deploy/restart gap, not a code bug
- **Frequency:** 2 sessions — `20260630-notif-debug`, `20260630-194500-notif-deploy`
- **Summary:** The spurious "Finished" push fix was already in `src/tmux.ts` and unit-tested, yet the bug still fired live. Root cause: the running `bun run src/cli.ts serve` process predated the fix (Bun has no hot-reload). The one command that disambiguated it instantly was comparing the process start time (`ps -eo pid,lstart`) against the source file mtime (`stat -f %Sm`).
- **Root cause:** lfg's server is a long-lived single process; restarts are deferred because a restart drops in-memory session tracking. So the running code lags the source often, and "already-fixed" bugs recur.
- **Current coverage:** Project CLAUDE.md notes a restart drops in-memory tracking, but does NOT tell you to check process-age-vs-mtime before re-debugging a recurring bug.
- **Recommended fix:** Add a project-CLAUDE.md hazard: for a recurring "already-fixed" bug, first compare running-process start time vs fixed-file mtime; if the process is older, restart, don't re-debug.
- **Mechanism:** project CLAUDE.md.

### 2. Ground-truth-first diagnosis (reinforced, already covered)
- **Frequency:** 2 sessions — `20260630-queued-pickup`, `20260701-codex-loading`
- **Summary:** Both bugs were solved fast by inspecting live state first (curl `/api/sessions`, read the on-disk rollout, scan the queue) instead of theorizing from code.
- **Current coverage:** Memory `ground-truth-before-hypothesizing` already captures this.
- **Recommended fix:** None — keep doing it. No new system entry.

## One-Off Observations (single session)

### 1. A full host disk silently halts ALL FlowDeck/Bash tooling (ENOSPC on the task-output write)
- **Session:** `scroll-autoscroll` / `20260630-180504-scroll`
- **Summary:** At ~148 MB free, every FlowDeck/Bash command failed with ENOSPC because the harness writes task output to a full `/tmp`. Looked like a tool bug; was environmental.
- **Worth persisting?** YES — the failure mode is opaque and recurs on a box running 20+ simulators + DerivedData across concurrent lfg sessions.
- **Recommended fix:** Memory: on repeated opaque ENOSPC/tool failures, check disk free first; surface as an environment issue rather than retrying.

### 2. Don't kill CoreSimulatorService mid-mount after `xcodebuild -downloadPlatform`
- **Session:** `scroll-autoscroll`
- **Summary:** `killall -9 CoreSimulatorService` + `scan-and-mount` during an in-progress 26.3.1 runtime mount discarded the image (7.8G→0) and surfaced a stale iOS 18.5 runtime — cost a full ~8GB re-download.
- **Worth persisting?** YES — non-obvious, expensive, iOS-ops-specific.
- **Recommended fix:** Fold into the same iOS-ops memory: after `-downloadPlatform`, let the mount finish untouched, then `simctl list runtimes`.

### 3. TestFlight ship doc omitted the rbenv activation step
- **Session:** `20260701-063459` (this session)
- **Summary:** `bundle exec fastlane` used system Ruby 2.6 and died on bundler 2.4.19; needed `eval "$(rbenv init - zsh)"`.
- **Worth persisting?** ADDRESSED this session — patched `.claude/testflight-setup.md` ship block.

### 4. Define success as the positive outcome, not suppression of the bad state
- **Session:** `20260630-queued-pickup`
- **Summary:** First fix marked dropped queued messages `failed` (a UI symptom fix) when the user wanted them *delivered* on idle. Re-drive on idle was the right shape.
- **Worth persisting?** Borderline — general engineering judgment, already implicit. NO new entry; noted here.

## Already Addressed

- [x] Spurious "Finished" push — fixed in `src/tmux.ts` (broadened `BUSY_METER`), `src/tmux-busy.test.ts` added. (`20260630-notif-debug`)
- [x] Queued-never-picked-up — hold-in-lfg + re-drive on idle; live-verified. (`20260630-queued-pickup`)
- [x] Interactive codex spins forever — `pickCodexThread()` promptless binding + 9 tests. (`20260701-codex-loading`)
- [x] Auto-scroll (send + open-while-running) — `SessionDetailView.swift`. (`scroll-autoscroll`)
- [x] TestFlight ship-doc rbenv step. (`20260701-063459`)

## Recommended Actions

| # | Action | Mechanism | Location | Priority |
|---|--------|-----------|----------|----------|
| 1 | Recurring "already-fixed" bug → check process start-time vs source mtime before re-debugging | project CLAUDE.md | `.claude/CLAUDE.md` (Architecture hazards) | HIGH |
| 2 | iOS-ops memory: opaque ENOSPC = check disk first; don't kill CoreSimulatorService mid runtime-mount | memory | new `ios-disk-and-runtime-ops.md` | MEDIUM |

## Logs to Archive (fully processed → delete, digest is the record)

- `improvement-log-20260630-notif-debug.md`
- `improvement-log-20260630-194500-notif-deploy.md`
- `improvement-log-20260630-queued-pickup.md`
- `improvement-log-20260630-180504-scroll.md`
- `improvement-log-scroll-autoscroll.md`
- `improvement-log-20260701-codex-loading.md`
- `improvement-log-20260701-063459.md`
- `improvement-log-20260701-051202.md` (empty)
- `improvement-log-20260701-askquestion-render.md` (empty)
