# Feature: iOS session view performance (scroll + input lag on long transcripts)

**Tier:** Product (shipping TestFlight client)
**Started:** 2026-08-18

## User Story

As someone driving agent sessions from the phone, I want the session view to stay
responsive — scrolling, typing, and menu actions — no matter how long the
conversation has grown, so that the sessions I use most (the long-running ones)
aren't the ones that are painful to use.

## Report

> "Session view is super laggy now scrolling input and other operations"

"Now" matters: the client hasn't changed the transcript-loading path, but the
transcripts have grown. Measured against the live host on 2026-08-18:

| msgs | JSON bytes | server fetch |
|---|---|---|
| 5000 (at the client's cap) | 3.95 MB | 86 ms |
| 3075 | 2.80 MB | 62 ms |
| 3035 | 2.62 MB | 67 ms |
| 2311 | 2.04 MB | 63 ms |

7 of 20 live sessions carry ≥1000 messages. The server answers in tens of
milliseconds — the cost is entirely client-side.

## Prior art

`.claude/diagnosis-needs-input-slow-transcript-20260806.md` (2026-08-06)
root-caused a related slowdown and named this exact amplifier:

> **Stop fetching the full transcript on open.** `LFGClient.messagesBackward`
> (`?page=backward`) is already implemented and **never called**. 220 messages =
> 134 KB vs 1.5 MB, and a far smaller `LazyVStack`.

Fixes 1 and 2 from that doc shipped; fix 4 (the amplifier) did not. Every
invalidation of `SessionDetailView` still pays for the whole transcript.

## Hypotheses (to confirm by profile, not by reading)

- **H1 — row count.** `SessionStore.loadHistory` fetches `limit: 5000, full: true`
  and `SessionDetailView.transcript` puts every message in one `LazyVStack`.
  Every parent body pass rebuilds `Array(messages.enumerated())` and re-diffs
  5000 identities; `withAnimation { scrollTo("BOTTOM") }` resolves intervening rows.
- **H2 — invalidation blast radius.** `draft` is `@State` on `SessionDetailView`,
  so every keystroke re-evaluates the whole body, transcript subtree included.
  Same for every SSE `msg` delta while the agent streams.
- **H3 — per-row cost.** `TextBubble.media` re-runs `MediaScanner.scan` on every
  body pass, and `prose`/`displayText` each call it again and compile a fresh
  `NSRegularExpression` per media ref. `ProseView` re-parses markdown
  (MarkdownUI) with `textSelection(.enabled)`.

Measured against real transcript data (release build, Apple silicon, scratch
benchmark over the 5000-message transcript): decode 23.6 ms, ForEach id
materialization 0.35 ms/pass, MediaScanner 76 ms total across 1049 text turns
(worst single turn 3.0 ms). So the *pure* parsing work is not the headline — this
points at H1/H2 (SwiftUI invalidation over 5000 rows) over H3, and the live
profile has to settle it.

## Success Criteria

- [x] SC0: A baseline profile of the shipped behavior attributes the main-thread
  cost of (a) scrolling and (b) typing in a ≥3000-message session —
  **Verify by:** `sample` of the app process while driving the interaction, hot
  main-thread stacks recorded in the evidence dir. **→ see Phase 0 result below.**
- [x] SC1: Opening a long session loads a bounded window (not 5000 messages), and
  the view still opens at the newest message —
  **Verify by:** unit test on the windowing/paging logic + screenshot of the
  opened session at the latest turn.
- [x] SC2: Scrolling up past the loaded window pages older messages in, without
  losing scroll position or duplicating rows —
  **Verify by:** unit test on the merge/paging logic + recording of the scroll-up.
- [x] SC3: Typing a character in the composer does not re-evaluate the transcript
  subtree —
  **Verify by:** post-fix `sample` under sustained typing, compared against the
  SC0 baseline.
- [x] SC4: Post-fix profile shows no main-thread stall > 250 ms during scroll or
  typing on the same session used for SC0 —
  **Verify by:** post-fix `sample` + comparison table against baseline.
- [x] SC5: No behavioral regression in the surfaces that read the whole
  transcript — Files & Links sheet, the full-title card (first user turn),
  optimistic-send reconciliation, and auto-follow at the bottom —
  **Verify by:** unit tests for reconciliation/resource collection + live checks
  of each surface.

## Platform & Stack

- **Platform:** iOS (SwiftUI, iOS 26), app target `ios/LFG`, logic package `ios/LFGCore`
- **Tooling:** FlowDeck only (build/run/UI), simulator `cc-c86fbfcb`
  (`2F228096-243B-445A-8B3B-ACFAFF56653B`, iPhone 17 Pro)

## Steps to Verify

1. `flowdeck run --scheme LFG -S 2F228096-…` to build and install.
2. Point the client at the local host and open a ≥3000-message session.
3. Drive scroll and typing via `flowdeck ui`, profiling the app process
   throughout; record hot stacks.
4. `cd ios/LFGCore && swift test` for the package half.

## Implementation Phases

### Phase 0: Baseline (SC0) — DONE, H1 confirmed

Method: shipped code, Debug build on simulator `cc-c86fbfcb` (iPhone 17 Pro),
pointed at the live host. `sample <pid>` over the app process while `flowdeck ui`
drove six identical swipes. Same gestures, same build, only transcript size differs.

| session | main-thread busy | `LazySubviewPlacements.placeSubviews` samples |
|---|---|---|
| `c6caf322` — 150 messages | 1.1 % (69/6279) | 3 |
| `5eed500b` — 3075 messages | 9.5 % (733/7711) | 284 |

~20× the messages → ~95× the placement work. The hot main-thread stack during
scroll is `GraphHost.runTransaction` → `LazySubviewPlacements.placeSubviews` →
`LazyStack.place(subviews:)` → `ForEachList.applyNodes`: SwiftUI walking the
**whole** ForEach list on every scroll update. Cost tracks total row count, not
visible row count — which is exactly H1.

Typing measured 3.0 % busy on the simulator; that is not nothing but it is not
the headline, and it shares the same cause (any invalidation re-walks the list).

Process footprint with one 3075-message session open: **167 MB** (peak 182 MB).

Caveats recorded honestly: this is a Debug build on an M-series simulator, which
is several times faster than the phone the report came from. The measurement is
used for *attribution and ratio*, not for absolute frame timings — the ratio is
build-independent because both sides ran identically.

Evidence: `.claude/evidence/session-view-performance/` (`baseline-scroll.txt`,
`small-scroll.txt`, `baseline-typing.txt`).

### Phase 1: Bound the rendered window (SC1, SC2, SC4)

- Scope: the transcript renders a bounded tail (default 200 messages) instead of
  every message, and extends upward as the user scrolls into history, restoring
  scroll position on extend. `SessionStore`'s fetch is untouched, so every
  whole-transcript consumer (Files & Links, full title, reconciliation) keeps
  seeing everything.
- Windowing decisions live in `LFGCore` as a pure type with tests; the view holds
  only the current window size.
- Verification gate: `swift test` green, and a post-fix profile on the SAME
  session showing placement cost down to small-session levels.

### Phase 2 (conditional): trim the invalidation blast radius (SC3)

- Only if the post-Phase-1 typing profile still shows transcript work per
  keystroke: split the transcript into its own view so an unchanged `messages`
  skips the subtree when `draft` changes.

## Decision Log

- **Measure before fixing.** The prior diagnosis already names a likely cause, but
  it was written for a different symptom (open latency at a prompt) and the fix it
  recommends is large. A profile is cheap and decides which of H1/H2/H3 to spend
  the work on.
- **Bounded rendering, not bounded fetching.** The prior diagnosis recommended
  fetching less (`messagesBackward`). Bounding what SwiftUI renders is a smaller,
  safer change that attacks the profiled cost directly and keeps every
  whole-transcript consumer working unchanged. Fetch windowing stays available if
  memory becomes the next ceiling.
- **`jumpToTop` still expands to the whole transcript.** Silently redefining a
  shipped gesture to mean "top of what's loaded" seemed worse than keeping its
  meaning and making the cost opt-in. Flagged under Residual Risks.
- **The visual-evidence auditor subagent was not spawned**, per this session's
  standing instruction not to use the Agent tool unless asked. The equivalent
  verification was done inline and recorded above.
- **Scratch benchmark ran outside the repo** (`$SCRATCH/bench`, an SPM package
  depending on `ios/LFGCore` by path) rather than as a test in the repo, because
  another agent is concurrently editing `ios/` (see repo concurrency hazard).

## Verification Evidence

All measurements: simulator `cc-c86fbfcb` (iPhone 17 Pro), Debug build, live host,
session `5eed500b` (3075 messages), `sample <pid>` over ten identical swipes
(`--from 200,250 --to 200,720 --duration 0.3`). Both builds driven the same way.

### Scroll (SC4)

| build | main-thread busy | `placeSubviews` |
|---|---|---|
| BEFORE — every row in one LazyVStack | 43.5 % (3685/8466) | 1081 |
| AFTER — 200-row window, runaway paging | 19.6 % (1773/9024) | 227 |
| AFTER — 200-row window, guarded paging | **15.9 %** (1390/8726) | **164** |

`before-scroll2.txt`, `after-scroll2.txt`, `after-guarded-scroll.txt`.
2.7× less main-thread time, 6.6× less layout placement.

### Typing (SC3)

Twelve single-character insertions into the composer of the same session:

| build | main-thread busy | `placeSubviews` | `ForEachList.applyNodes` |
|---|---|---|---|
| BEFORE | 9.8 % (907/9298) | 30 | 36 |
| AFTER | 7.3 % (674/9273) | **3** | **3** |

`before-typing2.txt`, `after-typing2.txt`. Transcript work per keystroke is down
~10× to noise; the residual 7.3 % is keyboard/text-field machinery, unrelated to
the transcript. **Phase 2 is therefore not needed** — Phase 1 covered SC3.

### Paging (SC1, SC2)

- Opens at the newest message, unchanged from before — `scrolled-into-history.png`
  shows genuinely older content after scrolling up.
- The "Loading earlier messages…" row appears at the top of the window and pages
  history in — `paging-loader.png`.
- Instrumented extend counter (temporary build, since removed):
  **22 swipes → 1 extend**, and one further swipe → 1 extend.

### The bug this verification caught (SC2)

The first implementation auto-extended on the loader's `onAppear` with an
immediate `scrollTo` restore. Instrumented, that produced **5 extends from a
single swipe** (window 1000 → 1400): the restore is asynchronous, so the loader
was still on screen when its `onAppear` fired again. Scrolling up briefly would
have rebuilt the very list the change exists to avoid — the fix would have
"worked" in every screenshot while silently undoing itself.

Fixed with an `extending` gate plus a restore deferred until the prepended page
has laid out (50 ms), animations disabled. Re-measured: 1 extend per gesture.

### No regressions (SC5)

- **Files & Links** still spans the whole transcript — entries dated 56 m through
  13 h ago, far outside the 200-message window (`files-and-links-whole-transcript.png`).
- **Full-title card** still resolves the FIRST user turn, ~3000 messages behind
  the window (`full-title-first-turn.png`).
- **Auto-follow** verified against a live streaming session, which stayed pinned
  to the newest turn as content arrived (`auto-follow-live-session.png`).
- **Optimistic-send reconciliation** reads `messages`, not the window, and is
  untouched; covered by the existing package tests. Not exercised live — see
  Residual Risks.
- `swift test`: 354 XCTest + 84 Swift Testing cases green.
  `flowdeck build`: clean.

## Residual Risks

- Measured on an M-series **simulator** in a **Debug** build. The ratios are
  build-independent (both sides identical), but absolute frame timings on a phone
  will differ. Not yet confirmed on device or on a TestFlight (Release) build.
- **Sending a message was not exercised live** — doing so would have injected a
  real turn into one of Eugene's actual sessions. The send path is unchanged and
  unit-covered, but the optimistic-bubble-through-window interaction is unproven
  in the running app.
- **`jumpToTop` (double-tap the top third) still renders the whole transcript**
  by design, and the window stays expanded until the session is reopened. That
  gesture is now the one way back to the old cost, and it is fairly easy to hit
  by accident. If it turns out to be a nuisance in real use, the honest fix is to
  page upward from there instead of expanding in one shot.
- The store still fetches and holds all 5000 messages (167 MB footprint with one
  big session open). This change bounds *rendering* only. Fetch windowing —
  `LFGClient.messagesBackward`, implemented and still never called — remains
  available if memory becomes the next ceiling.

## Bugs

- ~~Auto-extend ran away: 5 pages per swipe~~ — fixed, see Verification Evidence.
