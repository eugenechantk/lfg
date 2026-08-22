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
6. Each response is bounded by encoded bytes as well as message count, because
   tool results vary dramatically in size.
7. A failed page waits and retries the same cursor once; already-merged pages
   remain visible and the load never restarts from the newest page.

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
- [x] SC6: Each history response targets at most 256 KiB of encoded message JSON,
  while one individually oversized message is still returned to advance the cursor.
- [x] SC7: A transient older-page failure retries the same `before` cursor and
  does not redownload the newest pages.
- [x] SC8: Session `codexy-165159-64263` renders recent messages promptly, reaches
  its first prompt, and clears the top history-loading indicator.

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
  - every request carries the 256 KiB response budget
  - a transient failure repeats the same cursor rather than restarting

### Server unit

- `src/sessions-message-stream.test.ts`
  - byte-bounded pages traverse every normalized message without duplicates
  - one oversized message still advances the backward cursor

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
- Bound pages by encoded JSON bytes rather than only message count.
- Own the single retry inside the cursor-preserving async iterator; the store
  preserves the existing local-store fallback for terminal failure.

## Residual Risks

- One individually oversized message can exceed the page budget because paging
  must always advance. Supporting strict bounds there would require chunking or
  separately fetching expanded tool output.
- Complete history still transfers every message and can take tens of seconds on
  a slow tunnel. Recent content arrives first, the top row reports progress, and
  cursor-preserving retries prevent that transfer from restarting.

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
- 2026-08-21: Exact-session server verification reduced the newest response from
  500 messages / 1,091,341 bytes to 140 messages / 249,242 bytes. Through the
  active Cloudflare route it completed in 0.755 seconds with 63,118 wire bytes.
- 2026-08-21: The exact 1,154-message history completed in 15 bounded responses
  without cursor restart under variable tunnel bandwidth.
- 2026-08-21: Focused paging tests passed 5/5; the full LFGCore suite passed
  468/468; TypeScript type checking passed; server coverage passed.
- 2026-08-21: Independent post-restart audit passed. The exact session detail
  appeared at 1.79 seconds and recent transcript content at 2.767 seconds, then
  reached the original first prompt with no loading indicator remaining.
  Evidence: `.codex/evidence/20260821-013828-ios-visual-audit/evidence.md`.
