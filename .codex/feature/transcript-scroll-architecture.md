# Design: transcript scroll architecture

Phase 2 of the rethink Eugene commissioned after 202608230033 (still janky:
intermittent flicker, and scroll-up sometimes teleporting to the first few
responses). Phase 1 (instrumentation) is owned by session `50c624ca`. This doc is
**pure design — no code was changed for it.** Owner: `ff4c4e3c`.

Decision gate: Eugene picks the direction before any structural rewrite.

## The two constraints, stated as the product actually needs them

1. **Open shows the latest message**, and stays there while history loads.
2. **Older pages attach at the top** as you scroll up, without moving what you
   are reading.

Everything else in the current view is machinery invented to *maintain* those
two properties.

## Why the incremental approach ran out of road

Each fix this session closed a real, measured bug. The accumulation is the
problem. `SessionDetailView` now has **seven independent viewport writers**:

| # | writer | shape |
|---|---|---|
| 1 | `.scrollPosition(id: historyRevealAnchor)` | continuous binding, enforces while `extending` |
| 2 | `settleInitialBottomPin` | async loop, up to 90 frames (~1.44 s) |
| 3 | `followLatestUntilArrived` | async loop, up to 12 frames, fired from 3 `onChange` handlers |
| 4 | `holdViewportAcrossMutation` | anchor write + 300 ms hold |
| 5 | `extendWindow` | anchor write + 300 ms hold |
| 6 | `jumpToTop` / `jumpToBottom` | animated `scrollTo` |
| 7 | `.onAppear` + composer-send handler | direct `scrollTo("BOTTOM")` |

Writers 2 and 3 are per-frame loops with **no mutual exclusion**, and 1 can be
enforcing an anchor at the same time. That is the shape of the flicker.

The teleport has a matching structural explanation: the render window is a count
taken from the **newest** end, so `windowStart` moves as the total changes and an
anchor id the binding is holding can fall *out of the rendered slice*. An
unresolvable anchor plus a fixed `"TOP"` sentinel as the first row is exactly
"jumps to the first few responses". (Phase 1 should confirm by logging whether
the resolved anchor is still within `messages[windowStart...]` at each
transition — that is the discriminating line.)

**The root cause is categorical, not a list of bugs: viewport position is a
derived value that several components compute imperatively.** The way out is to
make the correct position *structural* — something nobody has to compute.

## Option A — inverted list

180° flip of the `ScrollView` and every row (`scaleEffect(y: -1)` or
`rotationEffect`). Newest message is array index 0 and renders at the visual
bottom. The industry chat pattern.

**Against the constraints:**

- Constraint 1 is **free**: "latest" is `contentOffset == 0`, the natural resting
  state. No pin, no settle, no arrival check.
- Constraint 2 is **free**: a history page attaches at the *visual top*, which is
  the **array end** — content grows away from the viewport, at offsets the user
  is not looking at. `contentOffset` is untouched, so nothing moves.

**What it deletes.** `settleInitialBottomPin`, `followLatestUntilArrived`,
`holdViewportAcrossMutation`, the anchor binding, and in `TranscriptWindow`:
`anchorAfterMutation`, `confirmsOpenArrival`, `openPinFrameBudget`,
`isScrolledToEnd`, `shouldSettleInitialPin`, and the whole `startIndex` /
window-from-the-end arithmetic (the window becomes a **prefix** — newest N — and
paging is a plain append). Writers 1–5 all go. That is most of what shipped
today, plus the concepts behind it.

**Honest limit — it is not "the viewport can never move".** A *new live message*
inserts at array index 0, i.e. at offset 0, which shifts existing content to
higher offsets. A reader scrolled up would still be displaced by that row's
height. Inversion converts the **large, frequent** problem (multi-hundred-row
history pages) into a free one and leaves a **small, rare** one (one short row,
usually while the user is at the bottom anyway). It should not be sold as
covering everything.

**Costs, in the order I expect them to bite:**

- *Text selection, context menus, link taps inside flipped rows.* The transcript
  has `textSelection(.enabled)`, tappable markdown links, attachment cards and a
  double-tap gesture. Hit-testing through a transform is the single biggest
  unknown and is what the spike must answer first.
- *Accessibility order.* VoiceOver would read newest-first. Fixable, but real work.
- *Keyboard avoidance* interacting with `safeAreaInset` under a transform.
- *Scroll indicators* point the wrong way — hide them (`.scrollIndicators(.hidden)`).
- *Insertion transitions* animate from the mirrored edge.

## Option B — native iOS 17+/18 stack

`defaultScrollAnchor(.bottom)` + `scrollTargetLayout` + `onScrollGeometryChange`,
with no manual `scrollTo` outside explicit user actions.

- Constraint 1: `defaultScrollAnchor(.bottom)` opens at the bottom.
- Constraint 2: on iOS 18, `defaultScrollAnchor(.bottom, for: .sizeChanges)`
  keeps the bottom edge pinned across content-size changes, so a prepend does not
  move the reader.

**Why I do not lead with it.** Two reasons.

1. **Deployment target is iOS 17.2.** `defaultScrollAnchor(_:for:)` and
   `onScrollGeometryChange` are iOS 18+. The load-bearing behaviour would exist
   only on 18, and iOS 17 falls back to the machinery we are trying to delete —
   two scroll models to reason about instead of one.
2. **It does not change the category.** Position is still *maintained* by the
   framework reacting to changes, and we still need geometry callbacks to decide
   follow-vs-not. It removes writers; it does not remove the class of bug. This
   is, in effect, the direction the incremental fixes were already converging on.

It is the cheapest option and a reasonable answer if the inversion spike hits a
blocker.

## Option C — UIKit bridge (`UICollectionView`)

`UICollectionView` + `UIHostingConfiguration` cells, preserving `contentOffset`
on prepend by the usual height-delta adjustment.

- Highest performance ceiling, and the only option that fixes the *placement*
  cost structurally: `LazyVStack` is lazy about rendering but **not about
  placing** — measured 150 → 3075 messages taking 3 → 284 `placeSubviews`
  samples (~95× for ~20× the rows). `UICollectionView` reuses and only lays out
  what is near the viewport, which is also the real answer to the 2 858 pt cell.
- Constraint 1 and 2 are both explicit code, but on well-trodden recipes.

**Costs:** by far the largest rewrite; we own more code; `UIHostingConfiguration`
self-sizing with heavy markdown has its own invalidation pitfalls; and for a
solo maintainer that is a lot of surface. It also keeps position imperative —
better-controlled, but still computed.

## Recommendation — Option A, with C as the named fallback

Eugene's two constraints map **1:1** onto inversion's two structural guarantees,
and it is the only option that deletes the concepts rather than re-implementing
them. It is also the smallest amount of *new* code: the change is mostly
subtraction.

Take **C** if the spike shows selection/context-menu/a11y behaviour through the
transform is not acceptable — C is the option with the best ceiling and no
transform weirdness, at the cost of size.

Take **B** only if we want the cheapest possible intervention and accept a split
iOS 17/18 behaviour.

## Spike plan (to run once Phase 1 lands and the tree is free)

Thin spike, real transcript data, on the ~1 400-message live session — answering
the questions that would actually kill the option, in this order:

1. **Hit-testing through the flip**: select text in a bubble; tap a markdown
   link; open an attachment card; long-press for a context menu; double-tap
   top/bottom bands.
2. **Prepend stability**: park mid-history, force several history pages in,
   measure a reference row's `y` — expect **0 pt**, with no anchor code at all.
3. **Open-at-latest**: cold open, measure the newest row sits just above the
   composer, and stays.
4. **Keyboard**: focus the composer at the bottom and while scrolled up.
5. **a11y**: VoiceOver order and rotor.
6. **Cost**: frame-advance during a paging scroll vs control, same metric as SC9.

Ship nothing from the spike; report and let Eugene choose.

## Phase 3 — required under all three architectures

None of these are fixed by any scroll model; all were measured this session.

1. **`TextBubble` compiles an `NSRegularExpression` per media ref inside `body`**
   (`prose` and `displayText`), so it re-compiles on every SwiftUI update for
   every visible cell. Precompute per message, cached by stable id.
2. **`messageStableIDs` rebuilds a `[String]` of the whole transcript** (cap
   5 000) on every body evaluation, purely to feed `.onChange`, which then
   compares the whole array. Track a cheap version token instead.
3. **A single tool-output cell measured 2 858 pt tall.** Cap the collapsed height
   with expand-on-tap (`ToolLineView` already has an `expanded` state and a
   `lineLimit(expanded ? nil : 3)` — the tall case is the *result* rows, which
   need the same treatment plus a hard `maxHeight` when collapsed).

Under inversion these matter *more*, not less: fewer viewport writers means
jank that remains is unambiguously per-frame cost.


---

# Phase 2 result + implementation (2026-08-23)

Eugene approved (a) and skipped the decision gate. Implemented against the
Phase-1 findings in `.claude/scroll-instrumentation-findings-20260823.md`.

## A blocking limitation, found and worked around

**`scaleEffect(x: 1, y: -1)` silently breaks hit-testing for controls inside the
flipped rows.** Taps on tool rows, "Thinking" disclosures and attachment cards
all did nothing — reproduced in BOTH the production view and the standalone
spike (which has no competing gestures), with BOTH synthetic taps and raw HID.

The discriminating control: the same attachment row in a *non-flipped* list
(Files & Links) responded instantly to the identical synthetic tap. So it is the
transform, not the input method or the control.

**`rotationEffect(.degrees(180))` does not have the problem.** Same layout, same
inversion, taps land: the attachment card opened its viewer, and a tool row
expanded 58 pt → 154 pt. This is the only reason the architecture is viable in
SwiftUI — worth remembering, because `scaleEffect(y: -1)` is the more commonly
cited recipe and it is the broken one here (iOS 26.3).

## Measured against the Phase-1 findings

| finding | before | after |
|---|---|---|
| F1 per-frame body re-eval from the `.scrollPosition(id:)` setter | setter fires every scroll tick → full body re-eval → rebuilds an N≈1,150 id array per frame | **binding deleted**; ids rebuilt only on a real mutation (store `transcriptVersion` token) |
| F2 follow bursts (12 × `scrollTo` per arrival, on unreliable `atEnd`) | flicker under churn | **deleted**; `atEnd` is now `offsetY <= 24`, which cannot be perturbed by content-height breathing |
| F3 open pin asserting 118 × and releasing blind | 118 `scrollToLatest` per open | **1 event per open, 0 scrolls** |
| F4 anchored page-reveal (was already correct) | ~60 pt compensation | no anchor needed at all — reveal is an append at the array end |
| F5 double-tap top band → `jumpToTop` renders whole transcript | teleport suspect | **removed**; no jump-to-oldest exists, nothing expands the window silently |

**Programmatic scroll writes during 10 scroll gestures: 0.** That is the metric
Eugene asked for, and it is zero by construction — the only remaining writer is
`jumpToNewest`, on an explicit double-tap of the lower band or on send.

## Viewport stability (own verification)

| case | result |
|---|---|
| open, long live session | newest row bottom y=698 vs composer 746 — correct, 1 writer event |
| parked in history, idle session, 3 samples / ~18 s | **identical y** — zero drift |
| parked in history, live session, across arrivals | **all 10 rows byte-identical** — zero drift |
| scrolling | 0 programmatic scrolls |

Note the live-arrival case came out better than the design doc predicted: I
expected an insert at index 0 to displace a reader in history, and it does not.

## Row-cost fixes (ship regardless)

- `TranscriptRowText.derive` computes media scan + the two regex strips **once**,
  memoised by stable id (`TranscriptRowTextCache`) — was compiled per ref, per
  row, per body evaluation.
- `messageStableIDs` no longer a computed property; store-side
  `transcriptVersion` token drives `.onChange`.
- Collapsed tool rows capped (`maxHeight: 64` + `clipped()`), tap-to-expand
  intact and verified. Tallest rendered row went **2,858 pt → 58 pt**.

## Still to verify (handing to the parent's independent rig)

- Text selection and markdown link taps inside flipped rows (attachment card and
  Button both work, so the mechanism is sound, but these are separate paths).
- VoiceOver reading order.
- Keyboard focus/inset behaviour at the newest end and in history.
- iOS 17 (`NewestEndTracker` is iOS 18+; `isAtBottom` stays `true` there, which
  only gates window growth).
