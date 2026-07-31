# Delegation Brief: session activity resolver (busy detection)

**Goal:** lfg's `busy` flag must be true whenever a session is actually working — including (a) long thinking stretches with no transcript writes, and (b) background Codex plugin delegations that outlive the Claude turn — while still dropping to idle within a few seconds of real completion.

Repo: `/Users/eugenechan/dev/personal/lfg` (Bun + TypeScript server). Design context (read them first):
- `.claude/feature/session-activity-detection.md` (success criteria + decision log)
- `.claude/brainstorm/session-activity-detection.md` (full audit of current busy paths)

## Problem (current behavior)

`busy` is computed in four places, all in the same Bun process, from weak or turn-scoped signals:

1. `src/sessions.ts` (~line 1116 and ~1204): REST baseline — `busy = last transcript message ts within 12s` (`REST_BUSY_WINDOW_MS`). False-idle during thinking; false-idle during background delegation.
2. `src/journal-pump.ts` `pollOne` (~lines 125–149): pane sessions use pane scrape `isBusy(pane)` (accurate mid-turn, false-idle once the turn ends during a delegation); pane-less use aisdk registry busy or a 4s transcript-mtime window.
3. `src/commands/serve.ts` legacy `/api/live/stream` poll loop (~lines 2133–2187): same logic as journal-pump.
4. `src/push/watcher.ts` `observeSession` (~lines 278–292): pane scrape / registry. Its busy→idle transition fires "finished / your turn" pushes — currently fires prematurely mid-delegation.

## Key fact: Codex plugin job state

A background delegation (`/codex:rescue --background`) spawns a task-worker that is **detached (parent pid 1)** — process-tree walking cannot attribute it. But the plugin persists job state at:

- Primary root: `~/.claude/plugins/data/codex-openai-codex/state/<workspace-slug>/state.json`
- Fallback root: `<os.tmpdir()>/codex-companion/<workspace-slug>/state.json`

Schema (observed live; be tolerant of missing fields):

```json
{
  "version": 1,
  "jobs": [{
    "id": "task-mreog6po-oby5ck",
    "status": "running",            // later "completed" / "failed"
    "phase": "verifying",
    "pid": 47627,                    // detached worker pid, may be null
    "sessionId": "ed5cba13-…",      // ← the DELEGATING CLAUDE SESSION ID (joins to lfg's session.sessionId)
    "workspaceRoot": "/Users/…/lfg",
    "updatedAt": "2026-07-10T08:40:34.535Z"
  }]
}
```

A job counts as an active delegation iff: `status === "running"` AND `sessionId` present AND `pid` present AND the pid is alive (`process.kill(pid, 0)` doesn't throw). Anything else (dead pid, null pid, completed/failed, malformed JSON, missing file) → not active. Jobs launched from git worktrees land in a **different** `<workspace-slug>` dir, so always scan **all** slug dirs under both roots and join on `sessionId` — never resolve a slug from the session's cwd.

## Spec

### New module `src/activity.ts`

Two small facilities, both process-global:

1. **Codex delegation scan.** `codexDelegationSessionIds(): Set<string>` — scans both state roots (every `*/state.json`), returns the set of `sessionId`s with an active delegation per the rule above. TTL-cache the scan result for ~2s (the files are tiny but this is called per session per tick). All I/O wrapped so a missing dir / unreadable file / bad JSON never throws. For testability, allow the state roots (and optionally a clock) to be injected — e.g. an internal `scanStateRoots(roots: string[])` that the public function wraps with the default roots + cache, so unit tests can point at fixture dirs without touching the cache.

2. **Pane-busy cache.** `notePaneBusy(sid: string, busy: boolean): void` and `lastPaneBusy(sid: string): boolean | null` — a Map of `{busy, at}` written by the pane-scraping loops each tick; `lastPaneBusy` returns `null` when there is no entry or the entry is older than 10s (scrapers tick every ~1s, so 10s staleness means the scraper isn't covering this session and callers must fall back). This is how the REST path gets pane accuracy WITHOUT spawning its own `tmux capture-pane` (listSessions is called every ~1s by the journal pump itself — adding pane captures there would double scrape load and risk the event-loop pileup documented in `src/journal-pump.ts`'s backpressure comment).

### Wiring (all four consumers)

Let `delegated = codexDelegationSessionIds().has(sessionId)` (skip when sessionId is null).

- `src/sessions.ts` claude-proc path (~1116) and codex-proc path (~1204):
  `busy = delegated || (lastPaneBusy(sid) ?? transcriptRecent)` where `transcriptRecent` is the existing 12s expression, used only when the pane cache has no fresh entry (pane-less sessions, scraper not running). aisdk path (~1288): `busy = e.busy || delegated`.
- `src/journal-pump.ts` `pollOne`: pane branch — compute `paneBusy = pane ? isBusy(pane) : false`, call `notePaneBusy(sid, paneBusy)`, then `busy = paneBusy || delegated`. Pane-less branch — `busy = (registry-or-mtime as today) || delegated`.
- `src/commands/serve.ts` legacy poll loop (~2133–2187): same treatment as journal-pump (both the pane and pane-less arms), including `notePaneBusy`.
- `src/push/watcher.ts` `observeSession`: OR `delegated` into the returned `busy` in both arms (pane-less registry arm and pane arm). This automatically fixes premature "finished" pushes and Live Activity "idle" — do not change the reducer logic itself.

Do NOT add any new wire fields — the existing `busy` boolean just becomes correct. Do NOT implement a ps/child-process signal (explicitly rejected — see feature doc Decision Log: long-lived background dev servers would pin sessions permanently busy).

## Constraints

- Bun runtime; match existing code style/comment conventions (this repo writes explanatory "why" comments at hazard points — keep that spirit, don't over-comment).
- Zero new dependencies.
- Keep changes additive and minimal — high-traffic files (`sessions.ts`, `serve.ts`) may have concurrent edits from other sessions; touch only the busy expressions and imports.
- Never let the new signals throw out of `listSessions` / the pump loops — everything try/caught or null-safe.
- Do not commit or push.

## Tests (bun test, colocate as `src/activity.test.ts`)

Use fixture dirs (tmp) with synthetic `state.json` files. Cover at minimum:

1. running job + live pid (use `process.pid`) → sessionId in the active set.
2. running job + dead pid (spawn a short-lived process and wait for exit, or use a known-free pid) → excluded.
3. running job + `pid: null` → excluded.
4. `status: "completed"` / `"failed"` with a live pid → excluded.
5. Job missing `sessionId` → excluded, no throw.
6. Malformed JSON / missing state root → empty set, no throw.
7. Multiple slug dirs (simulating worktree) → union of both.
8. Pane cache: `notePaneBusy` then `lastPaneBusy` → value; entry older than 10s → null (inject clock or make the TTL injectable).

Also update/extend any existing busy-related tests if wiring changes their expectations (`src/tmux-busy.test.ts`, `src/push/liveactivity.test.ts` should be unaffected — verify).

## Verification (run these; paste output in your report)

1. `bun test` — full suite green.
2. `bun build src/cli.ts --target bun --outdir /tmp/lfg-build-check` or the repo's typecheck equivalent (`bunx tsc --noEmit` if configured) — no type errors.
3. Grep-level sanity: all four consumers import from `src/activity.ts`.

Live probes (SC1/SC2/SC5 in the feature doc) will be run by the supervisor after your report — you don't need a live server.

## Definition of done

- [ ] `src/activity.ts` with the delegation scan (TTL-cached, injectable roots) and pane-busy cache.
- [ ] All four busy consumers wired as specified.
- [ ] `src/activity.test.ts` covering the 8 cases above; `bun test` fully green.
- [ ] No new wire fields, no ps-child signal, no committed changes.

## Report back

Files changed, `bun test` output, any deviations from the spec and why, anything left incomplete.
