# Subagent visualization in LFG

## Finding

Session `lfg-e6db43` maps to Claude session
`0df08cad-dc70-4b71-a588-35e86fe8ffa0`. It launched two depth-1 `Explore`
agents:

- **Map studio app architecture**
- **Map web media pipeline**

Both emitted a terminal `killed` task notification at 2026-08-20 12:51:46 HKT.
The parent AI-SDK harness is still alive but idle. They are therefore historical
subagents, not agents currently working.

Claude already persists everything needed to visualize them:

- Parent transcript: `<session>.jsonl`
  - `Agent` tool call = launch intent, description, prompt, and type.
  - `queue-operation` / `<task-notification>` = canonical lifecycle status and result.
- Child metadata: `<session>/subagents/agent-*.meta.json`
  - description, agent type, tool-use ID, spawn depth.
- Child transcript: `<session>/subagents/agent-*.jsonl`
  - live activity, timestamps, tool calls, and final response.

Observed terminal status vocabulary across local transcripts: `completed`, `failed`,
`killed`, and `stopped`; `running` also appears in task notifications.

## Recommendation

Visualize internal subagents inside the **session detail**, not as independent rows in
the main session list. LFG's existing `parentSessionId` nesting is for separately
managed LFG sessions; Claude sidechains share the parent's session ID and lifecycle.

### Collapsed state

Show one compact row immediately above the transcript:

```text
Agents   2 agents · 2 stopped                         ›
```

When any agent is active, prefer the active count:

```text
Agents   2 running                                     ›
```

### Expanded state

```text
▼ Agents
  ● Map studio app architecture       Explore     Running  1m 12s
    Reading studio/src/server/routes.ts

  ○ Map web media pipeline             Explore     Stopped  55s
    Stopped before producing a result
```

- Status dot: blue/animated = running, green = completed, orange = failed,
  gray = stopped.
- Primary label is the human description, never the opaque agent ID.
- Secondary line is the latest meaningful child activity, normalized with the same
  tool-cell rules as the parent transcript.
- Tapping a row opens the child transcript in a sheet or pushed detail view.
- Preserve the tree using `spawnDepth` if Claude begins emitting depth > 1 locally.

### Parent transcript

Replace the current raw `Agent: { ... }` tool cell and internal launch receipt with one
readable lifecycle cell that updates in place:

```text
Started agent · Map studio app architecture
Completed in 2m 08s
```

Do not expose the agent ID, output-file path, or Claude's internal instructions. The
current normalized transcript exposes all three in the `tool_result`; that is noisy and
contradicts the transcript's own instruction that this metadata is internal.

## Server contract

Add a read model derived from the files above:

```json
{
  "agents": [
    {
      "id": "stable opaque id",
      "toolUseId": "launch event id",
      "description": "Map studio app architecture",
      "agentType": "Explore",
      "spawnDepth": 1,
      "status": "stopped",
      "startedAt": 1787201451732,
      "lastActivityAt": 1787201506346,
      "finishedAt": 1787201506346,
      "latestActivity": "Reading studio/src/server/routes.ts",
      "resultPreview": null
    }
  ]
}
```

Recommended surface:

- `GET /api/sessions/:id/subagents` for initial hydration and child transcript links.
- A `subagents` payload on the existing session SSE stream for live lifecycle/activity
  deltas. Watch the parent JSONL plus its sibling `subagents/` directory while the
  session detail is subscribed.

Status resolution should be event-based, not inferred from process names or recency:

1. Match launch `Agent` tool calls to metadata by `toolUseId`.
2. Apply the newest task notification for that agent.
3. Map `completed` to completed, `failed` to failed, and `killed`/`stopped` to stopped.
4. Before a terminal notification, treat a launched agent as running.
5. Use child JSONL only for activity preview and transcript content, not terminal status.

This also handles resumed agents: task notifications explicitly say the same task ID
may stop and later resume, so the newest lifecycle event wins.

## Delivery slices

1. **Server normalization:** parse launch/notification events, hide raw internal launch
   receipts, add tests using completed/failed/killed/stopped fixtures.
2. **Read API + live deltas:** expose summaries and stream changes from child JSONLs.
3. **iOS panel:** collapsed summary, expanded cards, child transcript sheet.
4. **Desktop parity:** mirror the same information architecture after iOS behavior is
   verified.

## Acceptance checks

- `lfg-e6db43` renders two stopped Explore agents with their descriptions.
- A live pair changes from `2 running` to mixed/terminal states without reopening the
  screen.
- A completed agent exposes its final answer in the child transcript.
- A stopped then resumed agent returns to running and can complete.
- Parent transcript contains no raw agent IDs, temp output paths, or internal launch
  instructions.
- Sessions with no subagents render exactly as before.
