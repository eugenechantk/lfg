# Better session running/idle detection

**Problem:** lfg's running/idle status is wrong in two recurring ways:

1. **Thinking reads as idle.** During long thinking / silent tool stretches, no new transcript messages are written, so any surface that infers busy from "recent transcript message" flips to idle mid-turn.
2. **Codex delegation reads as idle.** When a Claude session delegates implementation to Codex in the background (`/codex:rescue --background`), Claude's own turn ends. No pane spinner, no transcript writes — but the delegated job is grinding away. The session is functionally running; lfg shows idle.

## How busy is computed today (audit)

| Path | Signal | Where | Failure mode |
|---|---|---|---|
| REST baseline | last transcript message ts within **12s** (`REST_BUSY_WINDOW_MS`) | `src/sessions.ts:1116,1204` | False-idle during thinking/silent tools; false-idle during delegation |
| SSE / journal pump, tmux panes | pane scrape `isBusy()` — spinner meter or "esc to interrupt" | `src/tmux.ts:803`, `src/commands/serve.ts:2181`, `src/journal-pump.ts:146` | Accurate mid-turn (incl. thinking), but **false-idle during background delegation** (turn is over, composer is empty) |
| aisdk / codex-aisdk | registry per-turn `busy` flag | `src/sessions.ts:1288` | Accurate for the agent's own turn; blind to background delegation |
| Pane-less bare CLI | transcript **mtime within 4s** (`BARE_BUSY_WINDOW_MS`) | `src/commands/serve.ts:2159`, `src/journal-pump.ts:134` | False-idle during thinking (no writes for minutes) |

The iOS client (`SessionStore.swift:725`) seeds busy from the REST baseline when a host's SSE link isn't delivering — so on a flaky multihost link, the weak 12s-transcript heuristic is what the list shows. The push watcher (`src/push/watcher.ts`) also keys "your turn" notifications off busy→idle, so both failure modes likely fire **premature "finished" pushes** while Codex is still working.

## Ground truth discovered

**The Codex plugin persists exactly the state we need.** A background delegation writes to
`~/.claude/plugins/data/codex-openai-codex/state/<workspace-slug>/state.json`:

```json
{
  "jobs": [{
    "id": "task-mreog6po-oby5ck",
    "status": "running",          // → "completed" / "failed"
    "phase": "verifying",
    "pid": 47627,                 // the detached task-worker pid
    "sessionId": "ed5cba13-…",    // ← the DELEGATING CLAUDE SESSION ID
    "workspaceRoot": "/Users/eugenechan/dev/personal/lfg",
    "updatedAt": "2026-07-10T08:40:34.535Z"
  }]
}
```

Two crucial facts:

- The task-worker is **parented to PID 1** (detached), so process-tree walking from the claude pid can NOT find it. The state file is the only reliable join.
- The job record carries the **delegating Claude `sessionId`** — a deterministic join to the lfg session, no cwd guessing needed.

Claude Code's *native* background shells (Bash `run_in_background`) are different: they stay **children of the claude pid**, so a `ps` snapshot finds them. MCP servers are also children but spawn at session start, so "child started >30s after the agent started" separates workers from helpers.

## Proposed design: one layered activity resolver

Introduce a single resolver used by **all** surfaces (REST `listSessions`, SSE `pollOne`, journal pump, push watcher, voice snapshot). Delegated/background work IS working — one state, no distinction on the wire:

```
activity(session) =
  working     if paneBusy || registryBusy          // agent mid-turn (covers thinking)
              || codexJobRunning(sessionId)        // plugin state.json join, pid verified alive
              || workerChildAlive(pid)             // shell child started after startup window
  blocked     if pending prompt (existing signal)
  idle        otherwise
busy = working                                     // existing wire field, now correct
```

Internally the resolver can note *which* signal fired (`source: pane | registry | codex-job | child-proc | transcript`) for logging/debugging, but that's diagnostic only — clients just see busy.

### Signal details

1. **`codexJobRunning(sessionId)`** — scan all `state/*/state.json` under the plugin data dir (plus the `$TMPDIR/codex-companion` fallback root), index `jobs[]` with `status === "running"` by `sessionId`. Guard against stale files: `kill(pid, 0)` to confirm the worker is alive; treat a dead pid as not-running. Cache with a 2–3s TTL — the files are tiny.
2. **`workerChildAlive(pid)`** — one `ps -axo pid,ppid,lstart` snapshot per tick (shared across all sessions, TTL-cached), build the child map, flag any live child of the agent pid whose start time is >30s after the agent's own start (excludes MCP servers / chrome-native-host spawned at startup). This covers native background shells and long foreground tool calls for *any* harness.
3. **Pane scrape in the REST path** — today REST busy never consults the pane. Reuse the journal pump's latest scraped busy (it already polls every pane) instead of capturing again, so `listSessions` stops depending on the 12s transcript window when a pane signal exists.
4. **Transcript recency** stays only as the final fallback for sessions with no pane, no registry, no pid.

### Surface changes

- **Session wire model:** no new field — the existing `busy` bool just becomes correct. iOS needs zero changes.
- **Push watcher:** "your turn / finished" fires on busy→idle; with the new signals folded into busy, the transition naturally moves to when the background job finishes and Claude's wrap-up turn ends. Premature mid-delegation pushes disappear for free.

## Alternatives considered

- **CPU% of the process subtree** — rejected: noisy (thinking is mostly network-idle), threshold-fragile.
- **Widening the transcript windows** (12s → minutes) — rejected: just trades false-idle for sticky false-busy; the user already saw the 12s flapping problem in the other direction.
- **Watching the codex job `logFile` mtime instead of state.json** — viable fallback but state.json already has status + sessionId; log mtime adds nothing.

## Risks / open questions

- Plugin data path is versioned by plugin name, not version (`plugins/data/codex-openai-codex/`) — stable across plugin upgrades, but the state schema is the plugin's internal format; pin a tolerant parser (missing fields → ignore job).
- Jobs launched from a **worktree** land in a different `<workspace-slug>` dir — scanning all state dirs and joining on `sessionId` (not cwd) handles this; the second state dir found during audit was exactly a worktree job.
- The 30s startup-window heuristic for child classification: an MCP server that restarts mid-session would read as a worker child → false busy. Acceptable; can refine with a command-name denylist if it bites.

## Verification plan

1. Unit: resolver with fixture ps snapshots + state.json fixtures (running / stale-pid / completed).
2. Live seam: start a `/codex:rescue --background` delegation in a test session; confirm `GET /api/sessions` shows `busy: true` for the delegating session the whole run and drops to idle only after the job completes **and** Claude's wrap-up turn ends.
3. Thinking case: fire a long-thinking prompt at a tmux session, confirm REST busy stays true past 12s of transcript silence.
