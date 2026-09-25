# Feature: Infinite Session Pagination

## User Story

As a user browsing or searching sessions, I can keep scrolling through older
pages without switching grouping mode or tapping a separate pagination control.

## User Flow

1. Browse the full session list under Status, Directory, or Host grouping.
2. Reach the bottom; the next ordinary closed-session page appends automatically.
3. Enter a search such as `noto`.
4. Reach the bottom; the next page of keyword matches appends automatically.
5. Continue until every relevant per-host cursor is exhausted.

## Success Criteria

- [x] SC1: Full-list pagination is list-level and works under Status, Directory,
  and Host grouping on iOS and macOS.
- [x] SC2: Search pagination is list-level and works under every grouping mode on
  iOS and macOS.
- [x] SC3: Reaching either footer requests its next page automatically and appends
  deduplicated rows.
- [x] SC4: Full-list and search cursors remain independent; entering search never
  advances or replaces the ordinary closed-list cursor.
- [x] SC5: A failed page leaves its cursor available for retry instead of marking
  that host exhausted.

## Test Strategy

- Existing host tests prove independent `before`/`nextBefore` search pages have no overlap or gaps.
- Swift package tests cover search matching and cross-host reconciliation.
- Build both clients and exercise a real `noto` search against the local host, verifying the backend cursor and client footer behavior in the running UI.

## Tests

- `src/session-search.test.ts`
  - `pages its own results with the before cursor, no overlap and no gaps` — SC2, SC3.
- `ios/LFGCore/Tests/LFGCoreTests/SessionSearchTests.swift`
  - reconciliation coverage — SC1, SC4 data invariants.
- Simulator/macOS UI evidence
  - search in directory grouping exposes and advances the list-level pager — SC1, SC2, SC3.

## Implementation Details

- Place both iOS pagers after all rendered sections rather than inside the Closed
  status section.
- Trigger the appropriate page request when its footer appears.
- Keep full-list and search loading flags/cursors separate in each client store.
- Preserve tappable search/footer controls as retry paths where present.

## Pagination Model

Each host owns two independent `before` cursors:

- ordinary cursor: `/api/sessions/resumable?limit=<n>&before=<timestamp>`
- search cursor: `/api/sessions/resumable?limit=<n>&q=<terms>&before=<timestamp>`

The first search request has no `before`. The host refreshes its incremental
transcript index, matches the query across title, project, working directory,
last-user preview, and indexed user turns, then sorts matching closed sessions
newest-first. It returns one page plus `nextBefore`, the last returned match's
activity timestamp when older matches remain.

When the search footer appears, the client sends the same `q` with that host's
`nextBefore`. Results are appended per host, then reconciled across hosts to
deduplicate synced transcripts and remove sessions that are live anywhere. A
nil cursor removes that host from further search pagination. The ordinary list
uses the same loop without `q` and never reads or mutates the search cursor.

## Residual Risks

- The audit exercised the first UI page advance and verified that the following
  backend page still carried a cursor. It did not scroll through the entire real
  corpus until cursor exhaustion.

## Verification

- `bun test src/session-search.test.ts src/sessions-resumable.test.ts`: 26 passed.
- `swift test --filter SessionSearchTests`: 13 passed.
- Full `swift test` in `ios/LFGCore`: passed, including 191 Swift Testing tests.
- `flowdeck build`: passed for the iOS simulator target.
- `desktop/build.sh` plus `--desktop-feature-test`: built and passed 136 assertions.
- Live API probe: two 20-row ordinary pages and two 20-row exact Noto-search
  pages, with zero overlap in either sequence.
- Independent iOS visual audit: PASS; both ordinary and exact-path Noto search
  completed two consecutive automatic page advances in Directory grouping.
  See `.codex/evidence/20260925-132606-ios-visual-audit/evidence.md`.

## Bugs

- iOS full-list pagination was nested under `section.group == .closed`; Directory
  and Host grouping never set that field, so those modes could not expose it.
- Search had the same placement bug before its pager was moved list-level.
