# Delegation Brief: closed-sessions pagination (server + iOS) and closed sessions on desktop

## Goal

Every Claude Code session stored on disk must be reachable from the clients' list views. Today the server truncates the closed-session list (default 30, hard cap 100 of ~271 transcripts), iOS only ever asks for the newest 60, and the desktop app doesn't fetch closed sessions at all. Full diagnosis: `.claude/diagnosis-missing-sessions-in-list.md`.

Three parts: (1) cursor pagination on the server's resumable endpoint, (2) iOS "Load more" paging in the Closed section, (3) desktop shows closed sessions and clicking one resumes it in a fresh tmux session (the existing `Opener.open` resume path).

## Constraints

- Repo: `/Users/eugenechan/dev/personal/lfg` (Bun server in `src/`, iOS in `ios/`, desktop in `desktop/`).
- Do NOT commit or push. Leave changes in the working tree.
- Other lfg agent sessions may be editing files concurrently. Keep edits scoped to the files named below, minimal and additive. If a file was modified since you read it, re-read and re-apply.
- Do NOT restart the running `lfg serve` process (it holds in-memory session state). For server verification, start a separate ephemeral instance on an unused port (check `src/cli.ts` / `src/commands/serve.ts` for the port flag or env var; default port is 8766, so use something like 8971).
- All API changes must be backward compatible: old clients send no `before` param and ignore `nextBefore`.
- Match surrounding code style and comment density (this codebase explains *why* in comments).

## Spec

### Part 1 — server: cursor pagination on `GET /api/sessions/resumable`

Files: `src/sessions.ts` (`listResumable`, ~line 1392), `src/commands/serve.ts` (endpoint, ~line 1470).

- `listResumable` gains an optional `before` (epoch ms). When set, only transcripts with `mtime < before` are candidates. Ordering stays newest-mtime-first. Keep the per-page clamp (min 1, max 100, default 30).
- The function (or the endpoint layer — your call, keep it clean) must also expose whether more candidates remain beyond the returned page, and the cursor to fetch them: `nextBefore` = the mtime of the last returned session when more remain, else `null`.
- Endpoint: parse `before` from the query string (float ms). Response becomes `{ sessions, nextBefore }`. `sessions` shape is unchanged.
- Note `excludeIds` (live sessions) are excluded *before* pagination — that's existing behavior, keep it. It means a page can be shorter than `limit` even when more remain; compute `nextBefore` from "are there more candidates after this page", not from `sessions.length === limit`.

### Part 2 — iOS: paged Closed section with "Load more"

Files: `ios/LFGCore/Sources/LFGCore/LFGClient.swift` (`resumable(limit:timeout:)`, ~line 177), `ios/LFGCore/Sources/LFGCore/Models.swift` (`ResumableResponse`, ~line 321), `ios/LFG/SessionStore.swift` (resumable fetch ~line 518 and refresh tick ~line 600), `ios/LFG/SessionListView.swift` (sections render ~line 187).

- `ResumableResponse` gains optional `nextBefore: Double?`.
- `LFGClient.resumable` gains a `before: Double?` parameter (appended as a query item when non-nil) and returns the full `ResumableResponse` (update both call sites; there are exactly two, in `SessionStore.swift`).
- `SessionStore` paging model (per host, since each host paginates independently even though transcripts are synced):
  - Keep per-host state: the accumulated deeper pages (`[hostId: [ResumableSession]]`) and the next cursor (`[hostId: Double?]`, nil/absent = exhausted).
  - The periodic refresh (the `resumeTick` block, ~line 600) fetches page 1 per reachable host as today (limit 60), stores each host's `nextBefore`, and builds `closedCache` from page1 + that host's accumulated deeper pages. `MultiHost.reconcileResumable` already dedupes by sessionId, so overlap between page 1 and accumulated pages is harmless.
  - New `func loadMoreClosed() async`: for each reachable host that has a non-nil cursor, fetch the next page (limit 60, before = cursor), append to that host's accumulated pages, update the cursor, rebuild `closedCache` (same reconcile), call `rebuildSessions()`. Coalesce concurrent calls (ignore re-entry while one is in flight).
  - Expose `var canLoadMoreClosed: Bool` (any host has a live cursor) and `var isLoadingMoreClosed: Bool` for the UI.
- `SessionListView`: in the Closed group's section only, after the session rows, render a "Load more" row when `store.canLoadMoreClosed` — a button that triggers `loadMoreClosed()`, showing a `ProgressView` while `isLoadingMoreClosed`. Match the list's existing row styling.

### Part 3 — desktop: show closed sessions, click resumes in tmux

File: `desktop/LFGSessions.swift` (single-file app, built by `desktop/build.sh`).

- Fetch `GET /api/sessions/resumable?limit=100` from each host alongside the existing `/api/sessions` fetch (decode: `sessions` array of objects with `sessionId`, `cwd`, `project`, `title`, `lastActivityAt`, `lastUserText`; ignore `nextBefore` — no paging on desktop for now).
- Reconcile like the iOS client: `~/.claude/projects` is synced between hosts, so (a) dedupe closed sessions by `sessionId` across hosts, and (b) drop any id that is LIVE on any host.
- Represent them as list items marked closed (extend `SessionItem` or `APISession` with a client-side `closed` flag; synthesize an `APISession` with agent "claude", a placeholder pid, `busy: false`, `tmuxName: nil`). Row rendering: dimmed idle-style dot, same layout as live rows.
- Grouping: in Status mode add a "Closed" group after Idle; in Directory mode file them into their directory sections like any idle session. Search must include them.
- Click behavior: route a closed item through the existing `Opener.open` — with `tmuxName == nil` it already takes the resume branch (`tmux new-session -A -s lfgd-<id8> -c <cwd> claude --resume <id>` in a new iTerm2 window). That is exactly the desired behavior; verify the branch is reached for closed items and do not duplicate the logic.

## Verification (run these yourself before reporting done)

1. Server: `bun test` (if a test runner is configured — check `package.json`). Then start an ephemeral server on an unused port and walk the pagination with curl:
   - Page through `/api/sessions/resumable?limit=50` following `nextBefore` until it returns null.
   - Assert: no duplicate sessionIds across pages; `lastActivityAt` non-increasing across the concatenation; total unique ids ≥ 250 (there are ~271 top-level transcripts, minus live ones); a request with no params still returns 30 and the response still has a `sessions` array (back-compat).
   - Kill the ephemeral server afterwards.
2. iOS: the package + app must build. `cd ios && swift build --package-path LFGCore` for the core package if it builds standalone; for the app use `xcodebuild -project LFG.xcodeproj -scheme LFG -destination 'generic/platform=iOS Simulator' build` (or the FlowDeck CLI if available). Zero new warnings in changed files.
3. Desktop: `cd desktop && ./build.sh` must succeed.
4. Add/extend server unit tests for `listResumable` pagination if a test setup exists (check for existing `*.test.ts`); otherwise note their absence.

## Definition of done

- [ ] `GET /api/sessions/resumable?limit=50&before=<ms>` pages through ALL top-level transcripts with no dupes and a terminating `nextBefore: null`.
- [ ] Response without `before` is backward compatible (`sessions` array unchanged).
- [ ] iOS builds; SessionStore accumulates pages per host; Closed section shows a working "Load more" row that disappears when exhausted.
- [ ] Desktop builds; closed sessions render in both group modes, deduped and excluding live ids; clicking a closed session reaches the existing tmux-resume branch.
- [ ] Nothing committed.

## Report back

Files changed, the exact verification commands you ran with their output (especially the pagination walk numbers), and anything incomplete or ambiguous you had to decide.
