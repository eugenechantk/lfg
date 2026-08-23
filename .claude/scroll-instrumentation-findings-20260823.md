# Scroll Jank — Phase 1 Instrumented Findings (2026-08-23)

Live debugging on the session simulator (iPhone 17 Pro, iOS 26.3), app built from
tree with viewport instrumentation (`LFGVP` NSLog at every scroll writer +
bucketed scroll-geometry trace), driven against the real server over loopback,
using the busiest live session (this one) as the stress subject. Raw trace:
scratchpad `vplog.txt` (~500 events). Instrumentation is in the working tree,
uncommitted, marked PHASE-1.

## Finding 1 — every scroll frame pays a full body re-evaluation (the LAG)

`.scrollPosition(id: historyRevealAnchor)`'s setter fires on EVERY scroll tick
(`anchor.SET` lines stream continuously during a drag). Each write lands in
`@State scrollPositionID` → SwiftUI re-evaluates the entire SessionDetailView
body per frame — which rebuilds `messageStableIDs` (an N-element array, N≈1150
here), recomputes the window slice, and re-diffs the transcript ForEach. This
compounds the already-profiled per-row costs (regex compiled in every visible
row's body, 2,858pt tool cells). **Scrolling is O(transcript) per frame.**

## Finding 2 — follow bursts fight the finger (the FLICKER)

`followLatestUntilArrived` issues **12 non-animated `scrollTo(BOTTOM)` at 16ms
intervals per arrival**, and a busy session arrives constantly. Trigger
condition is `isAtBottom`, which on iOS 18+ tracks `atEnd` geometry — and
`atEnd` is unreliable under churn:

- observed flapping true→false within milliseconds at open (overscroll bounce,
  y=-80);
- content height "breathes" ±100–200pt at idle and swings by thousands during
  fast scroll (LazyVStack re-estimating unmeasured rows: 15600 → 8100 → 14700
  in adjacent samples), transiently satisfying the at-end predicate while the
  user is mid-history.

One spurious `atEnd=true` + one arrival = 12 frames of code scrolling DOWN
while the finger drags UP — exactly "it flickers and moves up and down really
quickly", worst on busy tool-heavy sessions (matches "a few sessions have it").

## Finding 3 — the open pin asserts 118 times and releases blind

One session open produced **118 `scrollToLatest` calls**: the settle loop
asserts BOTTOM every frame while history hydrates (total walked 12 → 62 → 491 →
901 → 1154), then `settleOpenPin.release` fired with `end=false` — released by
frame exhaustion, never by confirmed arrival, because `atEnd` bounced during
hydration. Every one of those 118 `scrollTo`s forces layout of unmeasured rows.

## Finding 4 — the anchored page-reveal itself WORKS

The one thing that held: crossing a window extension (+11,900pt of content
inserted above) compensated the offset within ~60pt. The reveal-anchor
transaction is not the jank source.

## Finding 5 — teleport-to-oldest: prime suspect is the double-tap band

`jumpToTop` is bound to a `SpatialTapGesture(count: 2)` on the **top 30% of the
transcript**, `simultaneousGesture` with scrolling; it renders the WHOLE
transcript (`window = messages.count`) and animates to the oldest message —
precisely "goes all the way up to the first few responses". Synthetic rapid
flicks did not trigger it (no `jumpToTop` in the trace), so this is unconfirmed
for real fingers — but it is the only code path that goes to the oldest rows,
and two quick human flick-touches in the top band are plausibly two taps. Needs
either on-device confirmation or (cheaper) telemetry/guarding in the next build.

## Verdict for Phase 2

The system's stability depends on continuously ASSERTING the viewport — pin
loops, 12-frame follow bursts, keyboard repin frames — because bottom-anchoring
is not structural, and the asserting machinery both causes the flicker (F2) and
races the user. The per-frame `@State` writes from `.scrollPosition(id:)` are
the lag floor (F1). This is strong evidence FOR the inverted-list architecture:

- bottom = structural start → open-at-newest and follow-latest are contentOffset
  ≈ 0, no assertions, no pin loops, no bursts;
- history prepend = structural append → cannot move the viewport, no reveal
  anchor, **no `.scrollPosition(id:)` binding at all** → no per-frame body
  re-evaluation;
- `atEnd` becomes `offset ≈ 0` — immune to content-height breathing at the far
  end.

Row re-measurement breathing (F2's amplifier) and per-row body cost remain real
under any architecture — the flip must ship together with the row-cost fixes
(cache the regex work outside body, cap giant tool cells, stop rebuilding
messageStableIDs per evaluation).

Independent of architecture, the double-tap band (F5) should lose its top-band
binding or gain a guard (e.g. require the taps to be stationary), and
`jumpToTop` should not silently expand the window to the full transcript.
