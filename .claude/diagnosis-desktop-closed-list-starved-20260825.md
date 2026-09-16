# Diagnosis — desktop shows only 9 idle / 7 closed (2026-08-25)

## Symptom

Desktop client shows 9 idle and 7 closed sessions. Eugene expects far more (weeks of
closed-session history across both hosts).

## Ground truth (measured, not inferred)

- Pro `/api/sessions`: 3 live — 1 idle (ff4c…, lfg), 1 busy (this session), 1 gbrain temp-cwd (hidden).
- Air `/api/sessions` (via CF + desktop's service token): 7 live, all idle.
  → visible idle = 2 + 7 = **9**. The idle count is correct.
- Pro `/api/sessions/resumable?limit=100`: 100 rows, **97 gbrain** (`gbrain-claude-cli-cwd-*`),
  3 visible after the hidden-dirs filter.
- Air same query: 100 rows, **92 gbrain**, 8 visible (7 of those are `lfg-autopilot-claude-cwd-*`
  noise, 1 real lfg session).
  → visible closed ≈ 3 + 8 − cross-host transcript dedupe = **7**. Matches the display exactly.

## Root cause

Filter-after-page starvation. `LFGSessions.swift:1168` fetches exactly **one** page of
`/api/sessions/resumable?limit=100` per host and never follows `nextBefore`. The hidden-dirs
filter (`~/.config/lfg-desktop/hidden-dirs.json`, currently `*/gbrain-claude-cli-cwd-*`) is
applied client-side **after** paging. The gbrain autopilot churns so fast that its transcripts
occupy 92–97% of the newest-100 window on both hosts, so the page is almost entirely rows the
client is about to hide. All real closed history sits behind the cursor the client never follows.

The server (`listResumable`, `src/sessions.ts:3343`) is behaving as designed — it pages by mtime
and exposes `nextBefore`.

## Fix options

1. **Server-side exclusion (recommended).** Add an exclude-glob param (or read the hidden set)
   to `/api/sessions/resumable` so filtering happens before pagination — a page of 100 means
   100 *visible* rows. Matches [[enforce-at-the-boundary]]; also fixes the iOS client, which
   pages the same endpoint.
2. Client backfill: keep following `nextBefore` until N visible rows accumulate. No server
   change, but with a 5k-transcript gbrain corpus this can mean dozens of requests per refresh.
3. Stopgap, zero code: add `*/lfg-autopilot-claude-cwd-*` to hidden dirs (it's currently NOT
   hidden — 7 of the Air's 8 "visible" closed rows are autopilot noise), and accept the starved
   list until 1 or 2 ships.

Root fix is 1; 3 is worth doing regardless because autopilot temp-cwd sessions are the same
class of noise as gbrain's.

## Fix shipped (same day)

Option 1 implemented:

- `src/hidden-dirs.ts` — TS port of `HiddenDirs.hides` (segment-boundary literals,
  ancestor-walking globs, case-insensitive), tests in `src/hidden-dirs.test.ts` mirroring the
  Swift suite.
- `listResumable`/`searchResumable` accept `exclude: string[]`; the exclude path pages over the
  search index (which already carries cwd for the whole corpus) and enriches only surviving
  rows, so filtering happens BEFORE pagination at no per-candidate read cost. Route parses
  repeated `exclude` params. Tests: `src/sessions-resumable-exclude.test.ts` (starved-window,
  cursor-continuation, segment-boundary, garbage-exclude cases). Full suite 733 pass.
- Desktop `fetchHost`/`fetchSearchPage` send `hiddenDirs.paths` as `exclude` params; local
  `visible()` filter kept as backstop for old hosts.
- Verified live on the Pro: the byte-for-byte URL the client's URLComponents builds returns
  100 visible rows, 0 gbrain leaks (previously 3 visible of 100). New build installed to
  /Applications and relaunched. Pro server restarted via serve-forever respawn.
- **Air deployed same day** via `ssh air` (the alias works even when the raw hostname and
  tailnet don't; Syncthing had already mirrored the edited files byte-for-byte, so no git push
  was needed). Child-process kill → serve-forever respawn; probe: 100 rows, 0 leaks,
  tmuxTarget intact on all 7 live sessions.

## Infinite scroll (same day)

- Desktop: `fetchHost` now returns `nextBefore`; SessionStore keeps deeper pages + per-host
  cursors outside HostState (so the poll replacing page 1 can't discard them, and can't rewind
  the cursor); a sentinel row at the list bottom auto-fires `loadMoreClosed()` on appear.
  Reuses `fetchSearchPage` with an empty query as the page fetcher. Built, installed,
  relaunched — scroll gesture pending Eugene's eyeball (screen locked, AX unavailable).
- iOS already HAD the paging machinery (`loadMoreClosed`, extra pages, cursors) — starvation
  just made each 60-row page ≈ 2 visible rows. Fix: `LFGClient.resumable` gains `exclude`,
  applied inside `fetchResumablePages` (the single choke point for first page, load-more, and
  search; the by-id deep-link lookup deliberately stays unfiltered). The closed "Load more"
  button also fires `.onAppear` → infinite scroll.
- iOS verified LIVE on the session sim (cc-f0c66d1d, iPhone 17 Pro) against both real hosts:
  hid gbrain dir + autopilot pattern via row swipes, closed list refilled with real sessions
  (lfg / inbox / fiftyworkout / preamble-demo) and auto-paged ~2 days deep with no taps.
  Bonus semantics proof on-screen: literal hide blocked only `…-1799` while the pattern hide
  blocked every `lfg-autopilot-claude-cwd-*` pid variant.
