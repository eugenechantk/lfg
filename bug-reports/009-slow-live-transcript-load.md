# Bug 009: Long live transcript remains slow after progressive history loading

## Status: FIXED

## Description

Opening the live Codex session `codexy-165159-64263` (`Workout player voiceover and timing`) still takes long enough for the transcript to feel unavailable. The newest page and loading indicator may appear, but the useful live transcript should become responsive quickly and older history should finish without excessive transfer or render delay.

## Steps to Reproduce

1. Start the iOS app with the configured live LFG hosts reachable.
2. Open session `codexy-165159-64263` (`01a01e5e-bbd6-7531-8c8d-27020a21efde`).
3. Observe time to first useful transcript content and time until the top loading indicator clears.
4. Scroll upward while history is loading.
5. **Observed:** the live transcript takes perceptibly too long to become fully available.
6. **Expected:** recent content is interactive promptly, older history loads with bounded latency, and rendering additional pages does not stall scrolling.

## Root Cause

The 500-message page limit does not bound response size. In this 1,154-message
session, the newest page is 1.09 MB decoded and tool results account for about
820 KB. Live Cloudflare requests for individual 500-message pages took between
3 and more than 15 seconds, crossing `LFGClient`'s 15-second read timeout.

When any older page fails, `SessionStore.ensureHistory` creates a new paging
sequence for its retry. That discards the failed `before` cursor and downloads
the newest pages again, explaining why reopening sometimes eventually exposes
the complete transcript.

## Success Criteria

- [x] History responses target at most 256 KiB of encoded message JSON while
  guaranteeing cursor progress for an individually oversized message.
- [x] A transient page failure retries the same cursor once without redownloading
  newer pages.
- [x] The exact session shows recent messages promptly, reaches its first prompt,
  and clears the top loading indicator in Simulator.

## Investigation Log

### Attempt 1

**Hypothesis:** This session is materially larger or contains heavier message payloads than the prior pagination reproductions, so the current fixed 500-message pages still have excessive time-to-first-page or merge/render cost.

**Changes:** None.

**Result:** Investigation started; resolved the tmux name to live session `01a01e5e-bbd6-7531-8c8d-27020a21efde` on `Eugenes-MacBook-Pro` in `/Users/eugenechan/dev/personal/fiftyworkout`.

### Attempt 2

**Hypothesis:** Count-only pages cross the client timeout, and the retry restarts
from the newest cursor instead of resuming the failed page.

**Changes:** Added failing regression coverage for byte-bounded server paging,
the iOS `maxBytes` request contract, and same-cursor transient retry.

**Result:** The live session contains 1,154 normalized messages. Its newest 500
messages total 1,091,341 decoded bytes; 190 tool results contribute 819,807 text
characters. Authenticated Cloudflare paging produced 3–15+ second individual
responses, confirming both the timeout risk and restart amplification.

### Attempt 3

**Hypothesis:** Bounding encoded response bytes and owning the retry inside the
paging iterator will make recent content prompt and allow older history to finish
without restarting from the newest cursor.

**Changes:** Added a 256 KiB encoded-message budget to backward history pages,
passed that budget from `LFGClient`, retried a transient page at the unchanged
cursor, and removed `SessionStore`'s whole-sequence retry. Added server and Swift
regression coverage.

**Result:** After the supervised LFG service restart, this session's newest live
Cloudflare page returned 140 messages / 249,242 decoded bytes / 63,118 wire bytes
in 0.755 seconds. All 1,154 messages completed across 15 bounded pages without a
cursor restart. Independent Simulator audit passed: exact-session detail appeared
at 1.79 seconds, recent content at 2.767 seconds, the original first prompt was
reachable, and the history-loading indicator cleared. Evidence:
`.codex/evidence/20260821-013828-ios-visual-audit/evidence.md`.
