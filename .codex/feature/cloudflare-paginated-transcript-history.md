# Feature: Cloudflare-safe paginated transcript history

## User Story

As the LFG iOS user, Eugene can open a long session through the Cloudflare
Tunnel and see recent transcript content promptly while the complete retained
history continues loading in bounded pages.

## User Flow

1. Open a session from the connected iOS session list.
2. The client requests the newest history page through Cloudflare Access.
3. The newest messages render as soon as that first page arrives.
4. The client walks backward through the existing pagination cursor, merging
   each page into the store without duplicating live-stream messages.
5. Loading stops at the beginning of the transcript or the existing 5,000
   message retention cap.
6. A failed page logs the failure, waits, and retries the history load once;
   already-merged pages remain visible.

## Success Criteria

- [x] SC1: Opening a long session never depends on one multi-megabyte
  `full=1` response; history uses backward pages of at most 500 messages.
- [x] SC2: The newest page is delivered before older pages so the session stops
  showing the empty “Connecting” state promptly.
- [x] SC3: Paging follows `nextBefore`, stops safely at completion or a repeated
  cursor, and returns no more than 5,000 messages per load attempt.
- [x] SC4: Every paginated request retains the configured Cloudflare Access
  headers.
- [x] SC5: The complete 4,029-message reproduction session loads through the
  real Cloudflare hostname in Simulator, including history older than the first
  500-message page.

## Test Strategy

Package-level async integration tests use a scripted `URLProtocol` boundary and
the real `LFGClient` pagination sequence. They verify request queries, page
ordering, cursor termination, repeated-cursor protection, the message cap, and
credential propagation. The full LFGCore suite guards unrelated transport and
model behavior. Simulator verification exercises the real Cloudflare Access
transport against the known 9.97 MB transcript.

## Tests

### Package integration

- `ios/LFGCore/Tests/LFGCoreTests/MessageHistoryPagingTests.swift`
  - newest page is yielded immediately, followed by cursor-addressed older pages
  - repeated cursors terminate instead of looping
  - final request shrinks to preserve the 5,000-message cap
  - each page carries Cloudflare Access credentials

### Existing regression suite

- `cd ios/LFGCore && swift test`

### Simulator

- Launch the private build against `https://lfg-pro.eugenechantk.me`.
- Open `Manual motion control generation` (`01a01999-…`).
- Verify recent messages render after the first page.
- After paging completes, use the transcript's jump-to-start gesture and verify
  the original first prompt is visible. (The durable cache intentionally keeps
  only 200 messages; complete history lives in `SessionStore` while open.)

## Implementation Details

- Add a bounded `AsyncThrowingStream` history-page API to `LFGClient`, built on
  the existing `messagesBackward` endpoint.
- Change `SessionStore.ensureHistory` to merge and persist each yielded page as
  it arrives. Keep union-by-stable-ID semantics so SSE and retry overlap remain
  harmless.
- Preserve the existing single retry and local-store fallback.

## Residual Risks

- The endpoint currently reparses the full transcript for each backward page;
  this costs about 0.3 seconds per page on the 4,029-message reproduction file,
  but network transfer dominates through Cloudflare.
- The real-device cellular path may differ from Simulator bandwidth; bounded
  pages prevent one oversized transfer from blocking all visible history.

## Bugs

- `bug-reports/007-cloudflare-full-transcript-load.md`

## Verification Evidence

- 2026-08-20: Focused paging suite passed all four Swift Testing cases.
- 2026-08-20: Full LFGCore suite passed with no failures (362 XCTest cases plus
  92 Swift Testing cases).
- 2026-08-20: FlowDeck built and launched the LFG scheme successfully on the
  dedicated iPhone 17 Pro Simulator.
- 2026-08-20: A previously uncached 3,340-message session replaced the empty
  connecting state immediately after its newest page arrived, then exposed its
  original first prompt after complete paging.
- 2026-08-20: The 4,029-message / 9.97 MB reproduction session loaded through
  the authenticated Cloudflare hostname and exposed its original first prompt.
  Evidence: `bug-reports/007-cloudflare-4029-message-history.mov` and
  `bug-reports/007-cloudflare-4029-message-history-after.jpg`.
- 2026-08-20: Anonymous control request remained rejected with HTTP 403.
- 2026-08-20: Independent iOS visual/runtime audit passed on the dedicated
  Simulator. It verified immediate non-empty render and original-first-prompt
  history on the 4,029-message session, plus visible transcript content on the
  user's exact `codexy-221150-93411` session. Evidence:
  `.codex/evidence/20260819-124100-ios-visual-audit/evidence.md`.
