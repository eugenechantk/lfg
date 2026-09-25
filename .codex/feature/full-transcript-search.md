# Feature: Full transcript prose search

## User story

Find a past session from words written by the user or assistant anywhere in its transcript, with the most useful sessions and matching excerpts first.

## User flow

1. Type a query in the existing session search field.
2. See matching live and closed sessions, with an excerpt of the best user or assistant message hit.
3. Scroll for more ranked results. New or changed transcripts appear in subsequent searches.

## Success criteria

- [x] SC1: Index every visible user and assistant prose message, including late messages in long transcripts; exclude thinking, tools, metadata, and injected wrappers. **Verify by:** parser and index tests with Claude and Codex fixtures.
- [x] SC2: Incrementally index appended transcript bytes, rebuild truncated or rewritten files, and remove deleted sessions. A watcher schedules updates; startup and periodic reconciliation repair missed events. **Verify by:** filesystem integration tests.
- [x] SC3: Search title, path, project, and full prose; return the best matching excerpt and role. **Verify by:** API and ranking tests.
- [x] SC4: Rank the complete matching session set, deduplicate messages into sessions, and page it without overlap. **Verify by:** ranked search integration tests across pages.
- [x] SC5: iOS and macOS use ranked search pages and preserve their ordinary list cursors. **Verify by:** Swift tests, client builds, and simulator search flow.
- [x] SC6: A real corpus prototype records index size and build/query time without modifying the live host database. **Verify by:** isolated benchmark output.

## Platform and stack

- Bun/TypeScript host, SQLite FTS5, Swift iOS/macOS clients.
- Index database is per host under `LFG_DATA` and can be rebuilt from transcript files.

## Decisions

- Index the prose already accepted by the transcript normalizer, then filter to user/assistant text. This keeps search aligned with what the app displays.
- Keep the existing resumable endpoint for ordinary and older-client search. Add a ranked search endpoint with an opaque cursor so ranked ordering does not depend on transcript modification time.
- Use a bounded in-memory result snapshot for consistent pages while the filesystem changes; a fresh query uses the newest index.
- Use the file watcher as a fast signal and periodic reconciliation as the correctness mechanism.
- While a cold index builds, the ranked endpoint returns 503 immediately; clients keep the search spinner active and retry every three seconds. The ordinary session API remains available.
- Keep a ten-minute search snapshot per active query. If it expires during a long reading pause, clients restart that host's query and replace its old pages.
- Existing hosts that lack `/api/sessions/search` continue to contribute their older metadata/user-turn search pages through a 404 fallback.

## Index and query algorithm

The host keeps `session-content.sqlite` in its local `LFG_DATA`. `files` tracks
the chosen transcript path, modification time, size, and last complete JSONL
byte. `message_meta` stores session, role, source byte, and timestamp; FTS5 stores
visible prose. The existing JSON index continues to carry title, project, path,
and older-client search behavior.

At startup, a recursive watcher is attached to the Claude and Codex transcript
roots. An event debounces into a reconcile; a 60-second reconcile catches missed
events and newly created roots. Reconcile enumerates unique session IDs, skips
unchanged files, parses only appended bytes, rebuilds a rewritten/truncated
file, and drops deleted sessions. Updates/checkpoints are committed in SQLite
transactions. Complete JSONL rows alone advance the checkpoint; oversized
rows are skipped without buffering an unbounded tool payload.
Watcher paths force a rebuild even when a rewritten file retains the same size
and modification time; this covers editor-style replacement and restored mtimes.

On a new query, the host retrieves FTS message hits and combines their covered
terms with title/project/path terms. All query terms must occur somewhere in a
session. It scores exact title, title phrase, path/project, best prose BM25,
user-role boost, number of matching messages, then recency. Results are grouped
by session ID, filtered for hidden directories and live leases, and frozen in a
bounded in-memory snapshot. `/api/sessions/search` returns a page and opaque
`nextCursor`; ordinary `/api/sessions/resumable` still uses timestamps.

Content matching uses FTS token prefixes. Metadata/path matching retains the
existing case-insensitive substring semantics. Search responses carry the best
visible excerpt, role, score, and a `searchMatched` flag so clients do not drop
a multi-message match while reconciling hosts.

## Verification evidence

- SC1-SC4: `bun test` across seven relevant files: 65 passed, 0 failed; the
  subsequent focused run after the same-metadata watcher repair: 12 passed,
  0 failed. `bunx tsc --noEmit --pretty false` passed.
- SC3-SC4: `LFG_PORT=18877 bun scripts/probe-ranked-search-http.ts` on a
  checked spare port returned HTTP PASS. Page one ranked the exact title first;
  page two returned an assistant-only prose hit with `matchRole: assistant`,
  `searchMatched: true`, and a distinct cursor. The isolated fixture/database
  were removed after the probe. A larger 125-session fixture returned pages of
  60, 60, and 5 with 125 unique IDs and no repeats.
- SC5: iOS `swift test --filter SessionSearchTests`: 14 passed. Full package
  `swift test`: exit 0, including 196 Swift Testing tests. `flowdeck run` built,
  installed, and launched the app on the isolated simulator;
  `desktop/build.sh` and `--desktop-feature-test` passed with 138 feature
  assertions. The independent [iOS audit](../evidence/20260926-002322-ios-visual-audit/evidence.md)
  passed: assistant-only fixtures appeared in search, scrolling crossed the
  first 60-result boundary and reached the final page without observed repeats,
  and clearing search restored ordinary-list load-more behavior.
- The larger legacy search/resumable suite passed 88/90 at its default five-second
  per-test timeout. The two lease tests also timed out in the untouched main
  checkout while scanning the live, growing corpus; both passed in the worktree
  with `bun test --timeout 20000 src/sessions-resumable-closed.test.ts`.
- SC6: `bun scripts/benchmark-session-content-index.ts --limit=500` sampled
  500 evenly spaced sessions from 11,969. It read 406,663,080 source bytes,
  indexed 2,883 visible messages in 3,690 ms, and produced a 4,702,208-byte
  database. Sampled `noto` and `keyboard` lookups took 1 and 0 ms. This is a
  sample, not a measured full-corpus database size. A subsequent isolated run
  indexed 11,969 of the then-current 11,970 sessions: 7,113,856,074 source
  bytes, 59,517 prose messages, a 105,996,288-byte SQLite database, and
  88,569 ms cold build. `noto` returned 2,510 message hits in 97 ms; `keyboard`
  returned 1,064 in 138 ms. The temp database was removed afterward.

## Residual risks

- The full cold build measured 89 seconds on this machine. The host warms it
  at startup and clients retry while it is building; first use during that
  window visibly waits for the complete corpus.
- The sampled FTS lookup is fast; a very common term can still return many
  matching messages and spend time ranking them on the host event loop.
- The isolated fixture supports search, not transcript-opening, so the UI audit
  verified discoverability and pagination but not opening an indexed fixture
  conversation. The real host will expose transcript opening after deployment.

## Bugs

None yet.
