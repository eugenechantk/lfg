# Diagnosis — List view missing stored Claude Code sessions (iOS + desktop)

**Date:** 2026-07-10
**Symptom:** The session list doesn't show all sessions Claude Code has stored on disk. Reported on both the iOS client and the desktop client.

## Ground truth

- `~/.claude/projects` holds **271 top-level session transcripts** (plus 85 subagent transcripts in nested dirs and 6 Syncthing `.sync-conflict` files — both correctly excluded).
- Live server check: `GET /api/sessions/resumable` returns **30** by default; `?limit=500` returns **100** (hard cap).
- Transcript mtimes are sane (newest-first ordering is correct), so this is not an ordering/sync-mtime bug — it's pure truncation.

## Causes

### 1. iOS — resumable list is capped at 60 per host, server caps at 100

- Server endpoint `src/commands/serve.ts:1470` → `listResumable` (`src/sessions.ts:1392`) clamps `limit` to `min(100, …)`, default 30.
- iOS main refresh requests `resumable(limit: 60)` (`ios/LFG/SessionStore.swift:524`); the deep-link path uses 80 (`SessionStore.swift:268`).
- At the current session rate (~83 transcripts written in the last 4 days), the newest-60 window covers only ~3 days. **Every session older than the 60th-newest transcript is silently invisible** — no pagination, no "load more".

### 2. Desktop — never fetches closed sessions at all

- `desktop/LFGSessions.swift` fetches only `GET /api/sessions` (the live-process list). It never calls `/api/sessions/resumable`.
- So the desktop app shows only sessions with a currently-running `claude`/`codex` process. Every closed/rebooted-away session is missing by design of the current code.

## Not the cause (checked and cleared)

- **Nested transcripts** (85 files) are all `…/<sessionId>/subagents/…` — subagent transcripts, correctly not listed.
- ~~**Non-UUID filenames** (6 files) are Syncthing conflict copies of existing sessions — correctly excluded by the UUID filter.~~ **Correction (found during fix verification):** the UUID filter was unanchored, so `<uuid>.sync-conflict-*` names passed it and the 6 conflict copies WERE listed as duplicate sessions. Fixed alongside the pagination work (`UUID_EXACT` whole-name match in `listResumable`).
- **mtime shuffling by the sync daemon** — current mtimes are plausible and newest-first; ordering is fine today.

## Recommended fix

1. **Server:** add cursor pagination to `/api/sessions/resumable` (e.g. `?before=<mtimeMs>`), or at minimum raise the clamp (the expensive enrichment — title/cwd reads — is only paid for the returned page, so the clamp mainly protects against one giant page; pagination removes the need for it).
2. **iOS:** page the closed-sessions list (fetch newest 60, then "load more" / infinite scroll via the cursor). A one-line stopgap: raise the request to `limit: 100` — but that only buys ~2 more days of history at current usage.
3. **Desktop:** fetch `/api/sessions/resumable` alongside `/api/sessions` and merge, deduping live ids — same reconcile rule as `MultiHost.reconcileResumable` on iOS.
