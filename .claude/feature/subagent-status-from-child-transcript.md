# Feature: subagent-status-from-child-transcript

## User Story

As Eugene watching a session in lfg, I want every child agent that is working
for that session to show as running, however it was started or restarted, so
that the session never reads idle or "done" while work is still going on.

## Problem

`src/subagents.ts` decided a child's status from the PARENT transcript: the
launch receipt, the `<task-notification>` and the sync tool_result. A child that
was resumed with SendMessage after its first notification kept that "completed"
forever, because a resume writes `{resumedAgentId}`, which the parser never
reads. Eugene (2026-10-16): fix it by reflecting the child's real state, not by
handling one more parent event.

## The rule

The child's own transcript (`<parent>/subagents/agent-<id>.jsonl`) is the
authority for whether the child is working. Its turn state comes from its lines:

- assistant with `stop_reason` `end_turn` / `stop_sequence` → turn closed
- any other assistant line (tool_use, thinking, streaming null) → turn open
- user line `[Request interrupted by user…` → turn interrupted
- user line that is a system notification (`[SYSTEM NOTIFICATION`,
  `<task-notification>`) → ignored: a notice delivered into a finished child is
  not work until the child answers it
- any other user line (prompt, coordinator message on resume, tool_result,
  image, skill text) → turn open
- attachments, system rows → ignored

Status:

1. If the parent recorded a lifecycle (notification or tool_result) at or after
   the child's last turn line, the parent's word wins. It knows how the child
   ended (completed / failed / killed), and older Claude Code versions wrote the
   final reply with `stop_reason: null`.
2. Otherwise the child decides: closed → completed, interrupted → stopped,
   open or no lines yet → running.
3. The 30-minute silence backstop stays: a "running" child silent for 30 min
   reads unknown.

Corpus check (216 child transcripts on the Pro, 2026-10-16): the rule agrees with
the parent record for all finished children once (1) is applied, and reads the
two live children as running.

## Success Criteria

- [x] SC1: A child resumed after its completion notification reads running
  while it works, and completed after it ends again. — **Verify by:** unit test
  `a resumed child reads running from its own transcript` + live: this
  session's resumed verifier transcript replayed through `listSubagentSessions`.
- [x] SC2: A child whose transcript ends with `end_turn` reads completed even
  before the parent's notification lands. — **Verify by:** unit test.
- [x] SC3: A system notification delivered into a finished child does not make
  it read running. — **Verify by:** unit test + the four real children with that
  shape.
- [x] SC4: An interrupted child reads stopped without a parent notification. —
  **Verify by:** unit test.
- [x] SC5: Every existing subagent test still passes (sync completion, async
  receipt, staleness, killed/stopped mapping, grouped notifications). —
  **Verify by:** `bun test src/subagents.test.ts`.
- [x] SC6: Over every child transcript on this Mac, no finished child reads
  running and every live child does. — **Verify by:** a script that runs the new
  `listSubagentSessions` over all parents and lists running children with age.
- [x] SC7: The real server reports a resumed child as running. — **Verify by:**
  a scratch `lfg serve` on a spare port reading the real `~/.claude/projects`,
  `GET /api/sessions` row for this session shows `runningChildAgentCount ≥ 1`
  while a resumed agent works.

## Platform & Stack

- Bun server, TypeScript. `src/subagents.ts`, tests in `src/subagents.test.ts`.

## Added during verification

- **A child waiting on its own background command is running.** The first
  live probe pushed `sleep 90` to the background and ended its turn; Claude
  Code notified "completed … stopped with background work of its own still
  running" and resumed it 87 s later. A closed child with a live background
  command of its own (no end notice in its transcript, output file open per one
  batched `lsof`) now reads running. The probe runs only when such a child
  exists.
- **Notifications are dated at enqueue.** The parent repeats each notification
  as a `queue-operation` remove when it reaches the model; with the new
  timestamp comparison a late remove could re-date an old "completed" past a
  resumed turn. Non-enqueue queue rows are skipped.

## Decision Log

- **Parent word wins only when it is newer than the child's last turn line.**
  That keeps old-version transcripts (no `end_turn`) and kill/fail outcomes
  correct, and lets any later child activity (a resume) override a stale
  "completed".
- **System notifications into a child are neutral.** Four real children got a
  notification a day after they finished and never ran again.
- **Production restart needs Eugene's OK.** A restart drops in-memory session
  tracking and expires waiting phone sign-ins; verification uses a scratch server.

## Verification Evidence

| SC | Action | Result |
|---|---|---|
| SC1–SC4 | `bun test src/subagents.test.ts` (6 new tests, incl. background wait and enqueue dating) | 29 pass, 0 fail |
| SC1 replay | Real verifier transcripts cut at 16:10Z (resumed 16:07:38, working) through `listSubagentSessions` | OLD code: `completed`; NEW: `running` |
| SC5 | `bun test src` | 1268 pass, 3 fail. The 3 read only `ios/LFG/SessionDetailView.swift` (another session's in-flight edits) or time out under suite load; a clean HEAD worktree fails the same set |
| SC6 | `corpus.ts` over all 216 child transcripts on the Pro | new: 205 completed, 3 failed, 8 stopped, 1 running (a live agent in another session, active 2 s ago), 0 unknown. Old code: same plus 2 `unknown` the new rule resolves (1 interrupted, 1 ended without notice) |
| SC7 foreground | Scratch `lfg serve` :8797 on the real `~/.claude/projects`; SendMessage resume with a 75 s foreground command; `/api/sessions/<id>/subagents` every 3 s | `running` ×25 from 16:29:09, then `completed` at 16:30:32 (child replied 16:30:27). Before the fix the same resume read `completed` throughout |
| SC7 background | Resume with a 60 s background command; child ends its turn at 16:31:33 | `running`, session row `busy=True, runningChildAgentCount=1`, until the child's "done" at 16:32:34; then `completed`, count 0 |

Logs: scratchpad `subagent-status/live-foreground.log`, `live-background.log`.
Production is NOT deployed yet (needs a server restart on both Macs).

## Bugs

_None yet._
