# Feature: Session open paints instantly

Client half of the transcript-load-speed work. The server half (gzip on the API,
3.5x less wire) is already deployed by session `50c624ca` and needs no client
change. Owner: session `ff4c4e3c`.

## User Story

As someone opening a session on my phone, I want the conversation on screen
immediately — not a "Connecting to live transcript…" placeholder while a page
crosses a relayed link.

## Success Criteria

- [x] SC1: Opening a previously-opened session paints from the local GRDB store
  before the network is consulted. — **Verify by:** `ensureHistory` ordering plus
  a live open of a cached session showing content with no placeholder.
- [ ] SC2: The same holds with the network unavailable. — **NOT VERIFIED, see
  Residual Risks.**
- [x] SC3: A never-cached session's first paint requests a much smaller first
  page, then continues at full page size through the same cursor. — **Verify by:**
  `MessageHistoryPagingTests` asserting the byte budgets and that the cursor walk
  is unchanged.
- [x] SC4: Merging a history page no longer rebuilds and re-sorts the whole
  transcript. — **Verify by:** `TranscriptHistoryPageMergeTests`, including an
  equivalence check against the exact implementation replaced.
- [x] SC5: A huge session (`019fff33`, 536 MB rollout) shows recent content fast,
  history completes, and scrolling stays smooth while pages arrive. — **Verify
  by:** Simulator timing + a 26 s scroll recording.

## Implementation

**1. Hydrate-first (`SessionStore.ensureHistory`).** `hydrateTranscriptFromStoreIfEmpty`
ran only when no host was reachable or after a page failed — the local copy was
treated as an offline fallback. It now runs *before* the network call. The slow
open was never the offline one; it was online-but-far-away, where the placeholder
showed for the whole first round trip while a complete copy sat in GRDB. Network
pages merge on top, deduped by stable id.

**2. Small first page (`LFGClient.messageHistoryPages`).** New
`firstPageByteLimit` (default 48 KiB vs the 256 KiB used for every other page).
First paint is the only page the user waits on; later pages land above content
already being read. The cursor walk is untouched, and a *retry* of the first page
keeps the small budget (it is still the page nobody has seen). Pass `nil` to opt
out.

**3. Incremental merge (`TranscriptMerge.merge`).** `mergeHistoryPage` rebuilt a
`[String: SessionMessage]` of the whole transcript, took `.values` (discarding all
order), and re-sorted everything — O(n log n) plus two full allocations *per
page*, on the MainActor, while the user scrolls, getting worse with every page.
History pages arrive newest-first, so each is entirely older than what is already
merged: it prepends. Both sides are already sorted, so the merge is O(m) for that
case and O(n + m) if timestamps genuinely interleave. `seen` is carried through
the same call rather than rebuilt from the merged keys, which was the other
per-page O(n) pass.

## Tests

`ios/LFGCore/Tests/LFGCoreTests/TranscriptMergeTests.swift` →
`TranscriptHistoryPageMergeTests` (11 cases) — prepend fast path, successive
pages, dedupe/overlap, empty and nil-timestamp inputs, interleaving, and a
randomised equivalence check against the replaced implementation — SC4.

`ios/LFGCore/Tests/LFGCoreTests/MessageHistoryPagingTests.swift` — 3 new cases for
the first-page budget (small first then full-size, retry stays small, opt-out
restores one uniform budget) — SC3.

Full package suite: **402 XCTest + 104 Swift Testing, 0 failures.**

## Verification evidence (iPhone 17 Pro, iOS 26.3, sim `5512CC75`)

| check | result |
|---|---|
| Cached session reopen | content present at the first observable sample, **no placeholder** |
| `019fff33` (536 MB rollout), never cached | placeholder at +1.35 s, content at **+2.5 s** |
| `019fff33` reopened (cached) | **67 rows at the first sample, no placeholder** |
| Scroll while pages arrive | 26 s recording, monotonic backward walk, no blank frames, no snapping; history loader gone at the end (history complete) — `.claude/evidence/20260822-keyboard-scroll/80-scroll-while-paging.mov` |

## SC6 (added) — open lands at the newest message and STAYS there — **MET**

### The defect, measured

| open | lowest content row's bottom edge (composer top = 746) |
|---|---|
| before, cold + live | **1504–1517** — i.e. ~630 pt *below* the fold, static for 28 s |
| before, warm | 720 — correct |

Intermittent, which is why it read as "may still be seeing".

### Root cause — found by instrumenting, after two wrong fixes

```
LFGDBG openPin RELEASING scrolledToEnd=true msgs=2 window=200
```

The opening pin released when the transcript held **two** messages.

`shouldSettleInitialPin` fires as soon as `messages` is non-empty, and on a cold
open that is whatever couple of rows the live stream delivers first. Two short
rows are shorter than the viewport, so `isScrolledToEnd` answered "trivially
yes" — correct for auto-follow, catastrophic as an *open* confirmation. The pin
released, the real ~600 rows arrived afterwards, and because `isAtBottom` is now
honest geometry (rather than the old latched anchor `onAppear`) auto-follow
correctly stayed off and nothing ever brought the reader back.

This is precisely the hydrate-first interaction to watch: the change alters *when*
content lands relative to the pin.

### Fix

`TranscriptWindow.confirmsOpenArrival` — a stricter twin of `isScrolledToEnd`
that refuses to confirm while the content is not yet taller than the viewport.
The opening pin now re-asserts `scrollTo` until that confirms (bounded by
`openPinFrameBudget`), instead of pinning twice and releasing on a timer.

Also applied the same verify-don't-assume shape to the append-driven follow
(`followLatestUntilArrived`), since a single `scrollTo("BOTTOM")` undershoots in
this `LazyVStack` and an undershoot silently turns auto-follow off.

### Verification (iPhone 17 Pro, iOS 26.3)

| case | result |
|---|---|
| cold cache, live session (~600 rows) | **714**, stable across 28 s of continued history loading |
| warm cache, live session | **714**, stable across 28 s |
| idle long session | **714**, stable across 24 s |

714 vs a composer top of 746 — the newest message sits 32 pt above the composer.
Recording: `.claude/evidence/20260822-keyboard-scroll/D0-cold-open-fixed.mov`.

Tests: `OpenArrivalConfirmationTests` (5) and `OpenPinBudgetTests` (3). Suite 423.

## SC8 (promoted from residual) — no viewport shift while tools complete — **MET**

Promoted from "residual" at Eugene's request: the ~121 pt juking is user-visible
on tool-heavy busy sessions.

### Both offered hypotheses were wrong, and cheap to disprove

- *"tool_use and its result do not share a stable identity"* — every message from
  the API carries a server UUID, and `stableID` returns it. Identity is stable
  across the tool lifecycle. Checked against 40 live rows: `without id: 0`.
- *"the row's text changes when it completes"* — the client never rewrites an
  existing row. The live path (`apply(.message)`) dedupes by stableID and returns
  early; `TranscriptMerge.merge` skips ids already present. (The *old*
  `mergeHistoryPage` did replace payloads — that path is gone.)

### Actual cause, measured

The render window is a count taken from the newest end, so `startIndex` moves
whenever the total changes. Instrumented on a real session while history loaded:

```
old=63   new=482   windowStart 0 → 282
old=482  new=840   windowStart   → 640
old=840  new=1235  windowStart   → 1035
old=1235 new=1421  windowStart   → 1221
```

Each step genuinely renders **older rows above** whatever is on screen and shoves
the visible text. `reconciled` keeps the row *count* honest but says nothing
about the top of the rendered slice moving.

### Fix

`TranscriptWindow.anchorAfterMutation` returns the row that was first-rendered
before the mutation, when (and only when) the rendered top actually moved and
that row still exists. The view applies the window change through
`holdViewportAcrossMutation`, which sets the identity anchor and the window in
one transaction — the same discipline `extendWindow` already uses for a
user-driven reveal, now applied to the arrival-driven one.

### Verification (iPhone 17 Pro, iOS 26.3)

Parked mid-history in a tool-heavy busy session while tools completed:

| check | result |
|---|---|
| 4 tool completions | all 7 visible rows byte-identical (−632, −564, −511, −422, −351, −363, −285) |
| ~30 s soak, 12 tool completions, 6 samples | reference row at **−511 every time**, zero drift |
| regression: open-at-newest | still 714, stable 28 s |

Recording: `.claude/evidence/20260822-keyboard-scroll/G0-toolheavy-no-juke.mov`.
Tests: `AnchorAfterMutationTests` (5). Suite 428.

## SC7 (added) — no flash / no scroll excursion on send — **PARTIAL, shipped unverified**

Confirmed by reading: the optimistic bubble and its resolved message **can never
diff**. They live in different `ForEach`es, are different view types, and carry
different identities — `PendingSend.id` (a client UUID) versus the server's
`stableID`. Resolution is therefore always a row destroy plus a row create at the
bottom of the stack, not an update.

Recorded a real follow-up send on a long live session
(`B0-send-flash-before.mov`): on the **busy/queued** path — where the message goes
to the pending strip rather than an inline bubble — there is **no flash and no
scroll excursion** on the current build.

The **idle** path, where `.sentBubble` puts a real bubble inline and it later
resolves into a transcript row, is the one that does the destroy/create.

**Change made (unverified in Simulator):** the send path's two scroll triggers
(`onChange(of: pending.count)` and `onChange(of: prompt)`) issued their own
*animated* `scrollTo` while the transcript path issued another. Two independently
animated scrolls over an insert-plus-remove is a plausible source of "scrolls up,
then settles back". Both now route through the same non-animated
`followLatestUntilArrived` as the transcript path, so they coalesce rather than
compete.

This is **not verified live**: reproducing the idle-bubble path needs a session
that is idle AND tall enough to scroll, and repeated attempts to build one
(scratch sessions) failed to materialise a transcript. The identity destroy/create
is untouched — the optimistic bubble is still keyed by a client UUID and the
resolved row by the server id, so they still cannot diff. Shipped in
1.3.0 (202608222224) on that basis.

## SC9 — scroll smoothness during history paging — **MET (with a caveat)**

Eugene's read: the device scroll-lag item and the merge cost are one bug —
stuttering exactly while history pages arrive. Tested directly.

Same 9-swipe gesture on the same long session, 14 s window sampled at 30 fps
(420 frames), counting frames where the UI actually advanced (`mpdecimate`):

| run | advancing frames | non-advancing |
|---|---|---|
| (a) scrolling **while history pages arrive** | 282 | 138 |
| (b) control, history fully loaded | 286 | 134 |

A **1.4 % difference** — paging carries no measurable smoothness penalty, so the
gap between (a) and (b) is closed by the merge rework (O(m) prepend instead of a
per-page dictionary rebuild + full re-sort) plus the arrival anchor (SC8). No
further profiling of decode / MediaRefs / GRDB write-through was needed.

Recordings: `J0-scroll-during-paging.mov`, `K0-scroll-control.mov`.

**Caveat, stated plainly:** this is a frame-advance proxy, not Instruments hitch
metrics — no `xctrace` in this environment. Most of the "non-advancing" frames
are the stationary gaps between spaced swipes, so the absolute counts are not a
hitch count; only the *between-run delta* is meaningful. And I did not re-run the
metric against the pre-fix build, so I have not proven it is sensitive enough to
have flagged the original problem. What it does show is that (a) and (b) are now
indistinguishable.

## SC10 — no stale "Not sent" after a successful retry — **MET**

### Cause

`applyAcceptance` — the shared "the host took this message" mutation — set
`confirmed = true` but **never cleared `failed` / `queuedOffline`**. So: a first
attempt fails transiently, `settleSendFailure` flags the row, a later redelivery
succeeds and lands in `applyAcceptance`, and the row stays flagged. The user sees
"Not sent" for a message the server has (matching the successful redeliveries in
`sendq.log`). `retryOutboxRow`'s own success path cleared them by hand; every
other success path did not.

### Fix

`applyAcceptance` now clears `failed`, `queuedOffline` and `failureReason` —
acceptance is proof the message is not un-sent, applied once for all callers.

### Full lifecycle audit (what Eugene asked for)

Every setter of a failure/queued marker, against its clear:

| setter | kind | cleared by |
|---|---|---|
| `markPendingFailed` (3 call sites + settle) | terminal | `applyAcceptance`, `retryPending`, `retryOutboxRow` success, reconcile `removePending`, `correlatePending` retire |
| `appendPendingFromOutbox(failed: true)` (past retry cap) | terminal by design | `retryPending` |
| `enqueueOutboxForTransport` guards (x2) | terminal | `retryPending` |
| `attemptCreate` catch (placeholder rows) | terminal | `retryPending` (re-attempts the create) |
| ack `.markFailed` | terminal, server-confirmed | `retryPending` |
| `settleSendFailure` requeued (`queuedOffline`) | transient | drain success, `retryPending`, `applyAcceptance` |

`applyAcceptance` was the only gap.

### A backstop I added and then REMOVED — worth recording

I first added `OutgoingSendFailurePresentation.showsNotSent(failed:confirmed:)`
in LFGCore as a safety net, resolving `failed && confirmed` in favour of
"delivered". **The audit showed that is wrong.** The ack `.markFailed` path sets
`failed = true` AND `confirmed = true` deliberately — here `confirmed` means "the
server answered about this message", not "it was delivered". The backstop would
have *suppressed a legitimate failure warning*. Reverted; `confirmed` is not a
delivery signal and must not be used as one.

### Verification (stub host on 8793, `/send` switchable by a flag file)

Re-run after the revert, so the **source fix alone** is what is under test:

| step | result |
|---|---|
| send while `/send` returns 500 | **"Not sent" + Retry + banner** — terminal case intact |
| flip stub to accept, tap Retry | retried message resolves to a normal bubble; remaining row is an ordinary queued row — **no "Not sent", no exclamation, no Retry** |

Evidence: `.claude/evidence/20260822-keyboard-scroll/L0-retry-cleared-source-only.png`.
Suite 428.

## Residual Risks

- **SC2 (network disabled) is NOT verified.** Making the client truly offline
  needs *both* Cloudflare hosts unreachable, because `readClient` routes reads to
  any reachable host. Attempting it through the Settings UI perturbed Eugene's
  real host configuration (a duplicate host entry was created); the config was
  restored to Pro-default + Air, both healthy and credentialed, and the test was
  abandoned rather than mutate it further. The offline path is exercised by the
  same one line of code as the online path — hydration now runs unconditionally
  before the network — so the risk is low, but it is unproven.
- **"<100 ms" is unproven.** A FlowDeck screenshot round trip is ~1.2–1.5 s, so
  the measurement floor is far above 100 ms. What is shown is the discriminating
  difference: a cached open never displays the placeholder, an uncached one does.
- Hydration is still gated on `transcripts[id]` being empty, so a session that
  already has a few live-stream messages in memory does not pull its full cached
  history until the network answers. That is pre-existing behaviour and the
  cold-launch case (the one that matters) is unaffected.
- The merge's tie-break changed from an unstable `sorted` to page-first ordering.
  Equal-timestamp rows could previously come out in either order; they are now
  deterministic. Covered by the randomised equivalence test.
