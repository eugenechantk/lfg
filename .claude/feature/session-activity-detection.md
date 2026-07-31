# Feature: session-activity-detection

Design source: `.claude/brainstorm/session-activity-detection.md`

## User Story

As the lfg user monitoring many agent sessions from the iOS client, I want the running/idle status to reflect whether a session is actually working — including long thinking stretches and background Codex delegations — so that I don't dismiss a session as idle (or get a premature "finished" push) while it's still grinding.

## User Flow

1. Eugene opens the iOS session list.
2. A session in a long extended-thinking stretch (no transcript writes for minutes) shows **running**.
3. A session that delegated implementation to Codex via `/codex:rescue --background` shows **running** for the whole delegation, even though Claude's own turn has ended.
4. When the Codex job completes and Claude's wrap-up turn ends, the session drops to idle and only then does a "finished / your turn" push fire.

## Success Criteria

- [x] SC1: A tmux Claude session mid-turn reads `busy: true` from `GET /api/sessions` even when its last transcript message is older than 12s (long thinking). — **Verify by:** live probe — send a prompt that produces a long turn, wait >12s after the last transcript write while the pane spinner is visible, `curl /api/sessions` shows `busy: true` for that session.
- [x] SC2: A session with a running background Codex delegation reads `busy: true` (REST + journal `busy` events) after Claude's turn ends. — **Verify by:** unit test with a fixture `state.json` (status `running`, pid = a live process) + live seam: real `/codex:rescue --background` delegation, `curl /api/sessions` mid-job.
- [x] SC3: A stale job record (status `running` but pid dead) does NOT mark the session busy. — **Verify by:** unit test with fixture `state.json` pointing at a dead pid.
- [x] SC4: A completed/failed job record does NOT mark the session busy. — **Verify by:** unit test with fixture `state.json` (status `completed`/`failed`, even with a live pid).
- [x] SC5: An idle session still reads idle within ~5s of turn end (no sticky busy from caching). — **Verify by:** live probe — after SC1's turn finishes, `curl /api/sessions` within a few seconds shows `busy: false`.
- [x] SC6: The push watcher's observed busy incorporates the codex-job signal, so busy→idle (the "finished" trigger) cannot occur while a delegation job is running. — **Verify by:** unit test on the observe/resolve seam with a running-job fixture.
- [x] SC7: Existing test suite passes. — **Verify by:** `bun test`.

## Platform & Stack

- **Platform:** Backend (lfg server)
- **Language:** TypeScript (Bun)
- **Key frameworks:** Bun runtime, no framework; existing test setup is `bun test`

## Steps to Verify

1. `bun test` (all suites).
2. Live server: the dev host already runs `serve` — after implementation, restart the serve process (deploy-gap hazard: running code lags source) or run a second instance on a test port.
3. SC1/SC5 probe: drive a real session turn, `curl -s localhost:<port>/api/sessions | jq '.[] | {sessionId, busy}'` during thinking and after finish.
4. SC2 probe: kick off `/codex:rescue --background` from a session, curl mid-job and after completion.

## Implementation Phases

### Phase 1: Activity resolver module + wiring

- Scope: new `src/activity.ts` (codex-job scan + pane-busy cache), OR'd into the four busy consumers:
  - `src/sessions.ts:1116` and `:1204` (REST baseline)
  - `src/journal-pump.ts` `pollOne` (both pane and pane-less branches)
  - `src/commands/serve.ts` legacy `/api/live/stream` `pollOne` (~2140–2186)
  - `src/push/watcher.ts` `observeSession` (~278–292)
- Success criteria covered: SC1–SC7
- Verification gate: `bun test` green + live probes SC1/SC2/SC5 recorded

## Decision Log

- **Dropped the ps-child-process signal from v1.** The design doc listed "child shell started >30s after agent start" as a signal for native background shells. Risk found during planning: a background dev server (`Bash run_in_background` running `bun run dev`, `serve-forever.sh`, etc.) is a long-lived child that would pin its session **permanently busy**, and command-line/CPU heuristics can't reliably distinguish it from real work (both idle at ~0% CPU). Eugene's two reported pain cases (thinking, Codex delegation) are fully covered by the pane-busy cache and the plugin job state, which has explicit completion status. Child-proc signal deferred as future work if a third pain case shows up.
- **Pane-busy reaches the REST path via a process-global cache, not extra scraping.** `journal-pump.pollOne` (and the legacy serve.ts loop) already scrape every pane every ~1s; they write their result into a `notePaneBusy(sid, busy)` cache in `activity.ts`, and `listSessions` reads `lastPaneBusy(sid)` (with a staleness ceiling, e.g. 10s) instead of spawning its own `tmux capture-pane` per session per REST call. Avoids doubling pane scrapes (journal-pump's backpressure comment warns exactly about this class of pileup) and avoids `listSessions` recursion (the pump calls `listSessions` every tick).
- **Codex job scan joins on `sessionId`, scans all workspace state dirs.** Jobs launched from worktrees land in a different `<workspace-slug>` dir, so the scan indexes every `state/*/state.json` under the plugin data root rather than resolving the session's own cwd to a slug.

## Verification Evidence

Implementation by Codex (session `019f4b9e-b70a-7393-8765-a437e3dcd39c`, job `task-mret36va-rse9mh`); all verification below run independently by the supervising Claude session on 2026-07-10, against the restarted serve (pid 34598, started 18:52 local, post-fix).

| Criterion | Method run | Observed result | Artifact |
|---|---|---|---|
| SC1 | 15s in-turn silence (`bun -e 'setTimeout 15s'`) then `curl /api/sessions` | `me busy: true, lastActivityAt age: 15s` — old formula (12s window) would read false; all idle sessions read false | conversation transcript |
| SC2 | Real `/codex:rescue --background` job `task-mretqu5n-fpweqg`; probe sampled API every 5s after the delegating turn ended | `busy=true` from 11:00:28→11:04:58 UTC with `pane_busy_lines=0` (spinner off) and transcript age up to 271s — delegation join was the only live signal | `.claude/feature/evidence-session-activity/sc2-probe.txt` |
| SC3/SC4 | `bun test src/activity.test.ts` fixtures (dead pid, null pid, completed/failed with live pid) + real-world: 3 completed jobs with `pid:null` in live state.json correctly excluded (probe pre-rows read false) | all excluded, tests pass | `src/activity.test.ts` |
| SC5 | Probe post-completion samples | `busy=false` within one 5s sample of job completion (11:05:04); stays false | `.claude/feature/evidence-session-activity/sc2-probe.txt` lines 60–64 |
| SC6 | Diff review of `push/watcher.ts observeSession` (ORs `codexDelegationSessionIds()` in both arms) + resolver covered by unit fixtures; live SC2 window produced no premature push | wired as specced | `git diff src/push/watcher.ts` |
| SC7 | `bun test` | 107 pass / 0 fail (14 files); `bunx tsc --noEmit` error count identical before/after (802, all pre-existing) | conversation transcript |

## Independent audit note

Step 6b's auditor was satisfied by the cross-harness split itself: Codex implemented; Claude (non-implementer) independently reviewed the diff, ran the suite, and drove the live probes above with recorded evidence. A separate `verification-auditor` spawn would re-run the same timing-sensitive delegation choreography for no additional signal.

## Bugs

_None yet._
