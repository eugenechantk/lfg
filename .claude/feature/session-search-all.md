# Feature: session-search-all

Search that spans **every** session on a host, not just the pages the client has
already loaded.

## User Story

As Eugene, I want the session search field to find any session I've ever run —
including ones far past the current pagination window — so that I can jump back
to old work by typing a word I remember, instead of tapping "Load more" until the
row I want happens to be in memory.

## User Flow

1. Open the session list. The list shows live sessions plus the first page(s) of
   closed/resumable sessions (60 per host).
2. Type a term into the bottom search field (e.g. `preamble`).
3. The list now shows:
   - live sessions matching the term (filtered locally, as today), plus
   - **closed sessions matching the term from the entire transcript corpus**,
     newest first — regardless of whether they were ever loaded into the list.
4. If there are more matches than the first search page, a "Load more results"
   footer appends the next page of matches.
5. Clearing the search restores the normal grouped list exactly as before.

## Success Criteria

- [x] **SC1: Search corpus is the whole host, not the loaded page.**
  `GET /api/sessions/resumable?q=<term>` returns a match that sits far outside
  the newest `limit` transcripts. — **Verify by:** `src/session-search.test.ts`
  fixture home with 12 transcripts where the only match is the oldest, requested
  with `limit=3`; plus a live `curl` against the running host for a term present
  only in an old session.
- [x] **SC2: Search has its own pagination.** The response carries `nextBefore`,
  and re-requesting with `before=<nextBefore>` returns the *next* page of matches
  with no overlap and no gaps. — **Verify by:** unit test walking all pages of a
  fixture corpus and asserting the concatenation equals the full match set in
  order; plus two chained live `curl`s.
- [x] **SC3: Multi-term queries AND across the searchable fields**
  (title, project, cwd, last user text). `foo bar` matches a session whose title
  has `foo` and whose project has `bar`. — **Verify by:** unit tests in
  `src/session-search.test.ts`.
- [x] **SC4: The index is incremental.** A second search re-enriches only
  transcripts whose `mtime`/path changed; unchanged entries are reused from the
  persisted index. — **Verify by:** unit test on the pure `planRefresh` diff
  (reuse/enrich partition) + an enrichment-call counter across two searches.
- [x] **SC5: iOS search surfaces beyond-pagination results.** Typing a term that
  matches a closed session NOT present in the loaded list makes that row appear.
  — **Verify by:** simulator (iPhone 17 Pro) — capture the loaded list, then type
  the term, screenshot the matched row.
- [x] **SC6: iOS search paginates.** With more matches than one page, a "Load
  more results" footer appears and appends further matches. — **Verify by:**
  simulator screenshot before/after tapping it.
- [x] **SC7: Clearing search restores the previous list.** No leftover search
  rows, grouping/sections identical to before. — **Verify by:** simulator
  screenshot after clearing.
- [x] **SC8: No regression to the existing resumable list.** — **Verify by:**
  `bun test` green (whole suite) and `cd ios/LFGCore && swift test` green.
- [x] **SC9: Search covers EVERY host, not just one.** A match that exists only
  on the second machine, far outside any pagination window, is returned. —
  **Verify by:** two scratch hosts with disjoint corpora + `SessionSearchTests`
  cross-host merge tests; simulator screenshot of the merged result.
- [x] **SC10: A host that ignores `q` cannot inject non-matching rows.** A fleet
  mid-rollout degrades to "that host contributes less", never "that host
  contributes noise". — **Verify by:** unit test with a 60-row unfiltered page;
  live repro with a scratch host that deliberately ignores the parameter.

## Platform & Stack

- **Platform:** Bun server (TypeScript) + iOS client (SwiftUI / Swift 6)
- **Key frameworks:** Bun HTTP, SwiftUI, `LFGCore` package
- **Corpus scale (measured on the Pro, 2026-08-11):** 5,318 claude transcripts,
  1.4 GB. Full enumerate = 10 ms; full head+tail enrichment at concurrency 24 =
  **431 ms warm**. That is cheap enough to refresh the index inline on a search
  request (coalesced), so no background timer is needed — which also respects the
  repo rule against `setInterval` fan-out on the single Bun event loop.

## Steps to Verify

1. `bun test` (server) and `cd ios/LFGCore && swift test` (client core).
2. Restart the host server (`serve-forever.sh` respawns on child exit) and probe:
   - `curl -s 'localhost:8766/api/sessions/resumable?q=<term>&limit=3'`
   - chain `before=<nextBefore>` for page 2.
3. Build/install the iOS app with FlowDeck on **iPhone 17 Pro**, type the term in
   the search field, screenshot the matched row, tap "Load more results",
   screenshot, clear the field, screenshot.

## Implementation Phases

### Phase 1: Server search index + endpoint

- Scope: `src/session-index.ts` (pure index logic: entry shape, query matching,
  cursor paging, refresh diff), wiring in `src/sessions.ts`
  (`searchResumable`), `q` param on `GET /api/sessions/resumable`, persisted
  index at `~/.lfg/session-search-index.json`.
- Success criteria covered: SC1, SC2, SC3, SC4, SC8 (server half).
- Verification gate: `bun test` green including new `src/session-search.test.ts`;
  live curl paging against the real corpus.

### Phase 2: iOS client wiring

- Scope: `LFGClient.resumable(q:)`, `SessionStore` search state (debounced query,
  per-host search pages, cursor, load-more), `SessionListView` union of local
  live matches + server search matches, search-specific "Load more results".
- Success criteria covered: SC5, SC6, SC7, SC8 (client half).
- Verification gate: `swift test` green; simulator screenshots for SC5–SC7.

## Decision Log

- **Extend `/api/sessions/resumable` with `q` rather than adding a new
  `/api/sessions/search` endpoint.** The response shape, the `before`/`nextBefore`
  cursor, and the client's `MultiHost.reconcileResumable` cross-host phantom-drop
  all apply unchanged; a second endpoint would duplicate all of it. Older clients
  that don't send `q` are byte-for-byte unaffected.
- **Search the same fields the client already searches (title, project, cwd, last
  user text) — not full transcript content.** The ask is "widen the corpus", not
  "change what matches". Full-text over 1.4 GB needs a real inverted index and is
  a separate feature; noted as follow-up.
- **Metadata index, persisted to `~/.lfg/session-search-index.json`, refreshed
  inline and coalesced** rather than a background timer. Measured full build is
  431 ms and incremental refresh is a 10 ms stat pass plus a handful of reads, so
  a request-time refresh keeps the index correct without a fan-out tick.
- **Live sessions stay client-side.** The server search returns closed/resumable
  matches only (same liveness rule as the unsearched list); the client already
  holds every live session in full, so it filters those locally and unions.
- **Multi-term = AND across the concatenated fields.** `preamble pane` should find
  the session about both, which single-substring matching cannot do.

## Verification Evidence

All commands run 2026-08-11 on the Pro against the real corpus (5,422 claude
transcripts + 372 codex rollouts). iOS evidence is from the session's dedicated
simulator (iPhone 17 Pro, `cc-733fdf8e`) driven through the real UI.

| Criterion | Command / action | Observed result | Artifact |
| --- | --- | --- | --- |
| SC1 | `bun test src/session-search.test.ts` — "finds a match far outside the newest page" | PASS. Fixture: 11 non-matching recent sessions + the only match oldest; `listResumable({limit:3})` does not contain it, `searchResumable` returns it. | test output |
| SC1 (live) | `searchResumable({q:"preamble"})` over the real corpus vs `listResumable({limit:60})` | PASS. All 6 hits have `inLoadedPage: false`; oldest loaded row is 2026-08-11T05:12 while every hit is from 2026-08-09. Unreachable before this change. | `.claude/evidence/20260811-session-search/server-live-probe.txt` |
| SC2 | `bun test src/session-search.test.ts` — pagination walk | PASS. Three pages concatenate to exactly the 5-item match set, no overlap, no gaps, `nextBefore` null only at the end. | test output |
| SC2 (live) | page 1 then `before=<nextBefore>` on the real corpus | PASS. `overlap: 0`, `page2AllOlder: true`. | `server-live-probe.txt` |
| SC3 | `bun test src/session-search.test.ts` — multi-term AND; `swift test` — `SessionSearchTests` | PASS both sides. `fix preamble` matches only the session with both; `preamble pane` matches none. Client and host use the same rule. | test output |
| SC4 | `bun test src/session-search.test.ts` — content rewritten with mtime restored | PASS. The second search does not see the rewrite, proving the unchanged entry was reused rather than re-read. `planRefresh` unit tests cover new/moved/modified/older/deleted/duplicate. | test output |
| SC5 | Simulator: typed `preamble` into the search field | PASS. Six `preamble-demo` rows from 1d ago appear — none of them in the loaded list. Server log shows the client issued ONE request (`limit=60&q=preamble`) for 8 keystrokes, so the debounce holds. | `02-search-preamble.jpg`, `01-list-before-search.jpg` |
| SC6 | Simulator: typed `lfg`, scrolled to the footer, tapped "Load more results" | PASS. Footer appears on a full page; tapping it issues `?limit=60&before=1785861546071.3748&q=lfg` and appends a second 60-row page. | `03-search-lfg-loadmore-before.jpg`, `04-search-lfg-loadmore-after.jpg` |
| SC7 | Simulator: cleared the field | PASS. Grouped list restored (Paused 1 / Working 3 / Unread 14, matching the baseline), no search rows left, and the footer reverts from "Load more results" to "Load more". | `06-cleared-list-restored.jpg`, `05-cleared-footer-reverts-to-load-more.jpg` |
| SC8 | `bun test` / `cd ios/LFGCore && swift test` | PASS. 482 pass / 0 fail (server, was 480 before this feature); 249 pass / 0 fail (LFGCore, was 244). `npx tsc --noEmit` clean. `flowdeck build` succeeds. | test output |
| SC9 | `swift test` — cross-host merge tests; two scratch hosts (:8791 real corpus, :8792 disjoint fixture) with the app configured for both, searched `zarquon` | PASS. All 4 matches — which exist ONLY on host B and are 4 weeks old — appear in the merged list. Both hosts' logs show the query; host A returned 0 rows, host B returned 4. Dedupe, live-id drop, and merge covered by unit tests. | `07-cross-host-search.jpg` |
| SC10 | Restarted host B with `VERIFY_IGNORE_Q=1` (answers with its ordinary page, like a build predating `q`), searched `zzz-nothing-matches` | PASS. Host B's log shows it returned **60 unfiltered rows**; the client rendered "No matching sessions". Without the re-filter those 60 unrelated sessions would have been shown as matches. | `08-stale-host-rows-rejected.jpg` |

### Performance (measured, not estimated)

| Case | Cost |
| --- | --- |
| Cold index build (first ever search) | 2,785 ms |
| First search after the 3s window lapses | ~532 ms — of which **320 ms is `listSessions()`**, the liveness precondition `listResumable` already pays today. Search adds no new class of load. |
| Typed burst (6 keystrokes, same window) | 287 ms then 34–37 ms each |
| Steady-state repeat search | 36 ms |



The running `lfg serve` (started Aug 9) predates this code and tracks 22 live
sessions, so it was left alone. Verification ran against a **read-only scratch
host** on :8791 that calls the real `listSessions`/`listResumable`/
`searchResumable` but serves nothing else — deliberately not a second `lfg
serve`, which would have started a second journal pump against the shared
`~/.lfg/journal.db` and a second sendq. The simulator's app was pointed at it
through the app's own onboarding screen.

**This feature is therefore not yet live for the real client** — see "Deploying"
below.

## Deploying — BOTH hosts

Search fans out to every live host, so every host has to serve it. A host still
running the old build answers `?q=` with its ordinary page; the client's
re-filter keeps that honest, but that host contributes only the matches that
happen to fall inside its newest 60 — i.e. it is effectively not searched.

Neither host runs this code yet:

| Host | Server started | Live sessions | State |
| --- | --- | --- | --- |
| Pro (this machine) | Aug 9 17:00 | 22 | code is here, uncommitted |
| Air | Aug 10 18:38 | 6 | at commit `142bce2`, needs pull |

Full deploy = commit + push on the Pro, pull on the Air, restart both servers.
Each restart drops that machine's in-memory session tracking (the tmux panes and
`claude` processes survive). Not done unprompted — it needs Eugene's go-ahead.

## Bugs

_None yet._
