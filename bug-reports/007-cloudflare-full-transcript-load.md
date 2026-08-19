# Bug 007: Full transcript fails to load through Cloudflare Tunnel

## Status: FIXED — verified 2026-08-20

## Description

After switching the iOS host from the direct/Tailscale path to the Cloudflare
Tunnel + Access hostname, opening a session can leave only the recent live
backfill visible instead of loading the complete transcript.

## Steps to Reproduce

1. Start with the private iOS build configured for
   `https://lfg-pro.eugenechantk.me` and its Cloudflare Access service token.
2. Open the live session list.
3. Open a session with a multi-megabyte transcript.
4. Wait for the history request to finish or fail.
5. **Observed:** the complete transcript does not become available; only the
   recent stream/backfill may remain visible.
6. **Expected:** the complete transcript is eventually available and earlier
   messages can be loaded in the session view.

## Root Cause

`SessionStore.ensureHistory` asks `LFGClient.messages` for up to 5,000 messages
with `full=1`. The server serializes those messages as one response. The largest
currently visible session is 4,029 messages / 9,970,204 bytes: loopback returns
it in 0.34 seconds, while the authenticated Cloudflare path had delivered only
8,372,803 bytes after 15 seconds. In the live Simulator build the same session
remained on “Connecting to live transcript…” for minutes even though `/api/events`
heartbeats, keepalives, and the session list stayed healthy.

The server already exposes backward transcript pagination with a 500-message
maximum. The same 4,029-message transcript transfers through Cloudflare as nine
pages in 22.9 seconds total; the newest 500 messages arrive in 3.47 seconds and
no individual request takes more than 3.68 seconds. The client simply was not
using that endpoint for its initial/full history load.

## Success Criteria

### 1. History uses bounded backward pages and yields the newest page first
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** `NEW` —
`ios/LFGCore/Tests/LFGCoreTests/MessageHistoryPagingTests.swift` → newest-first
scripted pagination case.

**Simulator verification:**
1. Build and launch the private app against the bundled Cloudflare host.
2. Open `Manual motion control generation` (`01a01999-…`).
3. Observe the detail screen and persisted message count.
4. **Expected:** transcript messages replace the empty connecting state after
   the first bounded page, before complete paging finishes.

### 2. Paging completes without duplication, cursor loops, or exceeding 5,000 messages
- [x] Verified in unit test
- [x] Verified in simulator

**Unit tests:** `NEW` —
`MessageHistoryPagingTests.swift` → completion, repeated-cursor, and cap cases.

**Simulator verification:**
1. Keep the reproduction session open until paging completes.
2. Use the transcript's jump-to-start gesture after paging completes.
3. **Expected:** the session's original first prompt is visible, proving content
   older than the newest 500-message page is present in memory. (The durable
   cache intentionally retains only the newest 200 messages.)

### 3. Cloudflare Access authentication is preserved on every history page
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** `NEW` — `MessageHistoryPagingTests.swift` → credential headers on
all scripted page requests.

**Simulator verification:**
1. Perform the reproduction through `https://lfg-pro.eugenechantk.me` only.
2. **Expected:** every page succeeds behind Access and the complete transcript
   loads; an unauthenticated control request remains rejected.

## Investigation Log

### Attempt 1

**Hypothesis:** The client still downloads as many as 5,000 normalized messages
in one JSON response. Cloudflare adds enough transfer latency that larger
responses exceed the client's 15-second read timeout, after which the single
retry repeats the same oversized request.

**Changes:** None yet.

**Result:** A representative 822-message response is 2,665,450 bytes. It takes
0.04 seconds over loopback but 6.44 seconds through the authenticated Cloudflare
path. This proves a material transport multiplier, but this sample remains below
the 15-second timeout; larger-session measurement and app reproduction are next.

### Attempt 2

**Hypothesis:** A larger real transcript turns the transport multiplier into a
visible app failure, while existing bounded pagination avoids the oversized
response.

**Changes:** None.

**Result:** Confirmed. The 4,029-message session is 9,970,204 bytes locally.
Authenticated Cloudflare transfer had only reached 8,372,803 bytes at 15 seconds.
The app stayed on the empty connecting screen for minutes while its stream stayed
healthy. Fetching the same transcript through `page=backward&limit=500` completed
in nine pages / 22.9 seconds, with the newest page arriving in 3.47 seconds.

### Attempt 3

**Hypothesis:** A pull-based page sequence will make the newest history visible
before requesting the next cursor and will complete the same transcript without
one oversized transfer.

**Changes:** Added `LFGClient.messageHistoryPages`, changed `SessionStore` to
merge/persist each page as it arrives, and added four async integration tests.

**Result:** Passed. A previously uncached 3,340-message session left the empty
connecting state immediately after its first page, then exposed its original
first prompt. The 4,029-message reproduction session also exposed its original
first prompt after paging completed through Cloudflare Access. The anonymous
control request still returns HTTP 403.

### Attempt 4

**Hypothesis:** The user's concrete idle tmux session
`codexy-221150-93411` is the same failure shape and is covered by the bounded
history path.

**Changes:** None; resolved the tmux name to session
`01a01a5d-356a-7bb3-b2d2-fb0b084ea52a` and added it to the independent runtime
audit.

**Result:** The session currently normalizes to 876 messages. Through the real
authenticated Cloudflare hostname it returns as two backward pages (500 + 376):
the newest page completed in 8.97 seconds and the complete history in 20.39
seconds. This fits the new progressive loader and no longer depends on one
2.6+ MB response before anything can render.

## Final Summary

The iOS client now consumes the server's existing backward transcript endpoint
as pull-based pages of at most 500 messages, merges each page into `SessionStore`
before requesting the next cursor, and preserves the existing 5,000-message cap,
retry, stable-ID deduplication, and local-cache fallback.

Verification passed in the focused paging suite, the complete LFGCore suite,
the FlowDeck build, authenticated Cloudflare probes, and the independent iOS
runtime audit. The audit covered both the 4,029-message primary reproduction and
the user's exact `codexy-221150-93411` session; each opened with visible transcript
content, and the primary session's jump-to-start reached its original first
prompt. Independent evidence is under
`.codex/evidence/20260819-124100-ios-visual-audit/`.
