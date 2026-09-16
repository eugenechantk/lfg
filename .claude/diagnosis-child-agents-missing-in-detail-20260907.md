# Diagnosis — list shows 👥N but the session view has no child agents (2026-09-07)

**Report (Eugene):** "Sometimes when the session has a people icon in the list item … I don't
see it in the session view; I also don't see child agent option in the more actions menu."

## The two surfaces read different things

| Surface | Source | Fallback when the read fails |
| --- | --- | --- |
| List row `👥 N` | `runningChildAgentCount` on the `GET /api/sessions` row (server folds sidecar agents with `status == "running"`, `withSessionWorkActivity`) | Row is served from the host's **last good snapshot** (`lastSessionsByHost`); the count is never blanked |
| Bar above composer + "Child sessions (N)" menu | `childAgentsBySession[sid]` ← `GET /api/sessions/<id>/subagents` via `readClient(forSession:)` (`SessionStore.refreshChildAgents`) | **None.** 404 → `[]`; any other error → keep what we had (nil on first load). Polled every 2–8 s |

Both are computed by the same server function on the same host, and a live probe (session
`340626a6`, two background `sleep 150` agents, polled every 2 s from spawn to completion)
showed **zero disagreement on the Pro** — `cac=2 | subagents: 2 ['running','running']`, then
`0 | ['completed','completed']`. So the divergence is not server-side classification.

## Root cause: read routing + sync lag + no fallback

`MultiHost.readRouteHost` sends a per-session **read** to the owner only while the owner is
`.live`; in `.connecting` / `.degraded` (every foreground return over the CF tunnel, every
blip inside the grace window) it goes to the "agnostic" host — the other Mac. The list keeps
showing the owner's frozen row, badge and all, because those states are not "known down".

The other Mac does not have the data. `~/.claude/projects` is Syncthing-synced, but live
files lag by minutes and brand-new sessions are absent for longer:

```
newest lfg transcripts on the Pro   17:12–17:13   → on the Air: MISSING (all five)
newest lfg transcript on the Air    16:53 (20 min old)
probe session 340626a6 (spawned 17:10) on the Air at 17:13: no transcript, no subagents/ dir
sidecar dirs: Pro 37, Air 35 — 340626a6 and 5894849f missing
Syncthing: connected both ways, completion 99.99999%, needItems 1  (it is not dead, just slow on hot files)
```

So while the owner is non-live: `/subagents` on the peer → `404 session transcript not found`
→ `refreshChildAgents` writes `[]` → bar hidden, menu entry gone, and the 8 s poll keeps
re-asserting `[]` until the owner is `.live` again. The transcript itself still renders
because `hydrateTranscriptFromStoreIfEmpty` falls back to GRDB — which is exactly why the
session view looks fine except for the missing agents.

Even with the owner live, an agent spawned seconds ago is invisible from the peer, so any
routing to the peer shows the stale/empty set.

## Not the cause (checked)

- `async_launched` misclassification — fixed 08-29, both servers run code newer than the fix
  (Pro proc 16:55 today, Air proc 11:44 today, both have `resultLifecycle`).
- Duplicate `<id>.jsonl` across project dirs (would make `findTranscriptById` pick a copy
  without sidecars) — none on disk.
- Client decode — `ChildAgentSession` decodes every field leniently; unknown status → `.unknown`.
- Deferred `UIMenu` staleness — `updateUIView` refreshes the element closure on every render.
- Codex sessions — `scansClaudeTranscript` gates the count to claude rows; no icon there.

## Fix options (not applied — Eugene asked for a diagnosis)

1. **Pin child-agent reads to the owner** (`client(forSession:)` semantics, or a
   `readRouteHost` variant that refuses the peer for sidecar data), and on failure keep the
   last snapshot instead of writing `[]`. Cheapest; matches the "send" rule's honesty.
2. **Carry the agent list on the session row** (`GET /api/sessions` already computes it —
   `withSessionWorkActivity` has the array in hand and throws away everything but the count).
   Then the list and the detail view can never disagree, the badge comes with its data, and
   the frozen-snapshot path serves both. Slightly larger payload per row.
3. Persist `childAgentsBySession` in GRDB like transcripts, so the peer's 404 has a fallback.

Recommendation: 2, with 1's "never write `[]` on a peer 404" as the belt.

## Fix applied (2026-09-07, same session)

Options 1 + 2 above, per `.claude/feature/child-agents-survive-host-routing.md`: rows carry `childAgents`, the client seeds from them (`ChildAgentSnapshotMerge.seed`), and the per-session read is owner-pinned with a peer 404 no longer written through (`applyFetch`). Pro server restarted with the change; the Air server and the TestFlight build still need the deploy.
