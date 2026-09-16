# Diagnosis — background agents don't nest under their parent session (2026-08-29)

**Report:** session `lfg-3b61b1` (`450421b0`) said "3 agents working"; the iOS client
showed no nested child sessions and the row read idle.

## Ground truth

| Source | Says |
| --- | --- |
| tmux pane `lfg-3b61b1` | `✻ Waiting for 3 background agents to finish` + 3 rows in the agent tray |
| `~/.claude/projects/…/450421b0…/subagents/` | 3 sidecar pairs written 16:51, `.jsonl` still growing |
| `GET /api/sessions` | `busy: false`, `runningChildAgentCount: 0` |
| `GET /api/sessions/450421b0…/subagents` | the 3 agents, `status: "unknown"` |

So discovery worked — **status classification** did not. Every client surface keys off
`status == "running"` (`runningChildAgentCount` → list badge, `ChildSessionsBarVisibility`
→ the bar above the composer), so "unknown" erases the nesting.

## Root cause

`consumeParentEventLine` in `src/subagents.ts` reads a child's lifecycle out of
`toolUseResult.{agentId,status}`. That reader exists for **synchronous** subagents, whose
completion has no `<task-notification>` and lives only in that row (bug 010).

A **background** launch writes the identical shape:

```json
{"isAsync": true, "status": "async_launched", "agentId": "ab4ed7c62146bf660", …}
```

`mapStatus("async_launched")` falls through to `"unknown"`, so the launch receipt was
recorded as the agent's lifecycle — every background agent was classified terminal the
instant it started. 39 such rows across the local transcripts; only 2 rows are the
synchronous `{status: "completed", isAsync: false}` shape the reader was written for.

Consequences: `runningChildAgentCount: 0` → no `👥 N` badge, parent not promoted busy,
child-sessions bar suppressed, and the push watcher saw no agent work at all. It self-heals
only when the real `<task-notification>` lands — i.e. after the agents have finished, which
is exactly when the nesting is no longer useful.

## Fix

`src/subagents.ts` — only a **recognised** status may record a lifecycle:

```ts
const resultLifecycle = mapStatus(resultStatus);
if (resultLifecycle !== "unknown") { events.lifecycleByAgentId.set(…); }
```

An async launch therefore records nothing, the child keeps its default `"running"`, and the
later `<task-notification>` still terminates it. Generalises past this one string: no future
unrecognised status can latch a live child terminal either. The 30-minute
`RUNNING_STALE_MS` backstop still covers a child that dies without a notification.

## Verification

Replayed the real transcript truncated to line 420 — the exact moment the three agents were
live (after the three `async_launched` rows, before their notifications), with the real
sidecars, clock pinned 30s past the last launch:

```
BEFORE (HEAD) | agents 3 | running 0 | parent busy false | childCount 0   (all "unknown")
AFTER  (fix)  | agents 3 | running 3 | parent busy true  | childCount 3   (all "running")
```

Plus a regression test in `src/subagents.test.ts` covering both halves (launch receipt keeps
it running; notification still completes it). `bun test src/subagents.test.ts
src/sessions-subagents-transcript.test.ts src/push/watcher.test.ts` → 76 pass, 0 fail.

## Deploy note

The running `serve` started **Aug 25 11:05**; the fix is not live until the process is
restarted (`lsof -nP -iTCP:8766 -sTCP:LISTEN -t`, kill by port, `serve-forever.sh` respawns).
No client change is needed — every nesting surface already renders correctly once the server
reports `running`.
