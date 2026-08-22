# Feature: Transcript stays put when the keyboard comes up

Client-side bug cluster surviving TestFlight 1.3.0 (202608221109), which already
contains `.codex/feature/session-history-scroll-anchor.md`. Owner: session
`ff4c4e3c` (`lfg-955908`). Server-side siblings are owned by `50c624ca` — see
`bug-reports/010-delegated-work-busy-regression.md`; do not re-diagnose those
symptoms here.

Priority order set by Eugene: **B2 first**, then B1, then B3.

| id | Symptom | Reported |
|----|---------|----------|
| B2 | Typing in the composer sometimes scrolls the whole transcript above the viewable area / makes it disappear | NEW on 1.3.0 |
| B1 | Transcript scrolling is laggy and jumps ahead of the finger, on DEVICE | survives 1.3.0 |
| B3 | `SessionStore.lastError` is assigned in 22 places and rendered nowhere — interrupt/send failures are invisible | deferred from bug 010 |

## User Story

As someone replying to an agent from my phone, I want tapping the composer and
typing to leave the conversation exactly where it was, so that I can see what I
am replying to while I write.

## User Flow

1. Open a long session; it settles on the newest message.
2. Tap the composer. The keyboard rises.
3. **The newest messages stay visible directly above the composer.**
4. Type. Live messages and background history pages arrive during this.
5. The transcript still does not move on its own.
6. Scroll up to read history, tap the composer again — the rows under the reader
   stay under the reader.

## Success Criteria

- [x] SC1: With the transcript pinned at the bottom, focusing the composer keeps
  the newest message visible immediately above the composer — the content does
  not scroll above the viewport. — **Verify by:** accessibility-frame assertions
  that the last message's `y` stays on screen across the keyboard transition.
- [x] SC2: With the transcript scrolled up into history, focusing the composer
  leaves the rows under the reader in place (no jump to top, no blank viewport).
  — **Verify by:** a named row's `y` before focus and after the keyboard settles.
- [x] SC3: Background history paging **while the keyboard is up** does not move
  the viewport for a reader who is scrolled up, and a bottom-pinned reader still
  auto-follows. — **Verify by:** deterministic `LFGCore` policy tests plus a
  forced-boundary Simulator run.
- [x] SC4: Dismissing the keyboard restores the same viewport (no second jump on
  the way down). — **Verify by:** the same frame measurements, continued through
  keyboard dismissal.
- [x] SC5: The existing scroll-anchor behavior is preserved — opening settles at
  the newest message, upward scrolling across a page boundary does not snap, and
  a manual scroll-up still disables auto-follow. — **Verify by:** the existing
  `TranscriptWindowTests` / `SessionFocusTests` suites plus a forced-boundary
  recording.
- [x] SC6 (B3): A failed store operation is visible on the phone instead of
  silent. — **Verify by:** driving a real server failure and capturing the
  banner.

## Test Strategy

The defect is a viewport-position bug, so the primary evidence is **measured
accessibility frames before and after the keyboard transition**, not screenshots
— "the transcript moved 407pt" is the claim, and only numbers prove it. The
decision logic underneath is lifted into `LFGCore` so it carries deterministic
regression cover.

## Tests

### Package Unit

- `ios/LFGCore/Tests/LFGCoreTests/TranscriptWindowTests.swift` →
  `KeyboardViewportPolicyTests`
  - `testBottomPinnedReaderIsRepinnedWhenTheKeyboardResizesTheViewport` — SC1
  - `testReaderInHistoryIsNeverMovedByTheKeyboard` — SC2, SC3
  - `testOpeningStillOutranksBottomAnchorVisibility` — SC5
  - `testHistoryAnchorIsEnforcedOnlyWhileRevealingAPage` — SC2, SC5
  - `testRepinSpansTheReportedKeyboardAnimation` — SC1
  - `testRepinAlwaysRunsAtLeastOnce` — SC1 (guards the fix against silently
    becoming a no-op on a missing/NaN duration)

### Runtime (iPhone 17 Pro, iOS 26.3, sim `5512CC75`)

Frame measurements across a real keyboard transition — SC1, SC2, SC4.
Forced page boundaries (`pageSize` temporarily 20) — SC3, SC5.
Real 404 from the host driving the banner — SC6.

## Implementation Details

Two independent defects, both in `SessionDetailView.transcript`.

**1. `.scrollPosition(id:)` was enforcing an anchor for the entire life of the
view.** It is a continuous contract, not a one-shot scroll: while bound to a
non-nil id, SwiftUI re-derives the content offset to hold that row at the anchor
across *every* layout change. The keyboard is such a change. Now bound through
`historyRevealAnchor`, which reports the id only while `extendWindow` is
revealing a page (`extending`, which already stays true for a 300 ms settle after
the window expansion) and `nil` otherwise. The setter still writes through, so
the anchor is up to date whenever the next reveal needs it.

**2. Nothing moved the content when the viewport shrank.** The composer hangs off
`safeAreaInset(edge: .bottom)`, so the keyboard takes ~300 pt and the newest
message went behind it. `repinForKeyboardChange` observes
`keyboardWillChangeFrame` and, only for a reader who is already at the newest
end, re-pins to `BOTTOM` across the animation. It re-pins for the whole
transition rather than once, because the notification arrives *before* the safe
area inset lands — a single scroll targets the pre-keyboard layout. It also
cancels `bottomDebounce`, so the anchor leaving the viewport mid-animation is not
mistaken for a deliberate scroll-up.

**3. (B3) `lastError` had no reader.** It is now a computed pass-through that
also stamps `errorEvent`, so all ~20 existing assignment sites surface without
being edited. A separate event was necessary because `refresh()` clears
`lastError` on every successful poll — a banner reading it directly would blink
out within a second. `SessionErrorBanner` presents it under the nav bar for 6 s,
tap to dismiss. Two silent-return guards (`run(_:for:_:)` and `interrupt`) now
set an error instead of returning quietly.

## Residual Risks

- **The page-reveal path could not be exercised at the shipping `pageSize` of
  200**: no session on this host currently exceeds 150 messages, so the boundary
  is unreachable with real data today. It was exercised by temporarily setting
  `pageSize = 20`, which drives the identical `extendWindow` code path. The
  reveal behaviour is also unchanged *by construction* — inside `extendWindow`
  the binding returns exactly what `$scrollPositionID` returned before, and
  `extending` already covers the documented 300 ms settle.
- **Device-only behaviour is unverified.** Everything here was measured in the
  Simulator. The keyboard geometry notification and `safeAreaInset` behave the
  same on device, but the reported lag (B1) is device-only and untested.
- **B1 (laggy scroll / jumps ahead on device) is NOT fixed.** See below.

## Defect 3 — found by following up "type while live messages arrive"

The keyboard fixes above were measured against an **idle** session. Re-running
the same scenario against a **live** one exposed a third, independent defect,
and it is the one that best matches "the transcript disappears entirely".

Measured on a live session, scrolled up, keyboard up, text typed: every row moved
**−146 pt per arriving message**, repeatedly. A few arrivals and what you were
reading is gone above the top.

`NSLog` instrumentation in `onChange(of: messageStableIDs)` gave the cause
directly:

```
13:17:57  follow=false  window 200->201  startBefore=365 startAfter=365   ← correct
13:18:11  follow=TRUE   isAtBottom=true  opening=false                    ← wrong
13:18:15  follow=TRUE   isAtBottom=true
13:18:31  follow=TRUE   isAtBottom=true
```

`TranscriptWindow.reconciled` was working perfectly (`startBefore == startAfter`).
The fault was `isAtBottom` being **true while the reader was hundreds of points
up**, which made every arriving message call `scrollTo("BOTTOM")`.

**Root cause:** `isAtBottom` was inferred solely from a 1 pt `BOTTOM` anchor's
`onAppear` / `onDisappear`. In a `LazyVStack` those fire when SwiftUI *creates* a
row, not when it becomes visible, so a large transcript mutation re-creates the
anchor off-screen and latches follow-mode on. It is intermittent — which is
exactly the reported "sometimes" — and it reproduced on one run and not the next
with identical gestures.

**Fix:** `isAtBottom` now comes from real scroll geometry via
`onScrollGeometryChange` → `TranscriptWindow.isScrolledToEnd` (iOS 18+; iOS 17
keeps the previous anchor behavior). Geometry cannot misreport this the way row
lifecycle can.

**Verification (instrumented build, live session):**

- Scrolled up + keyboard up + typed, across 5 live message arrivals:
  **zero** `FOLLOW` events. The transcript is never dragged.
- Pinned at the bottom: `FOLLOW` events fire normally on each arrival and the
  newest message stays directly above the composer — auto-follow is intact.

**Residual, honestly stated:** on a live session a uniform ~121 pt shift remains
across several arrivals. It is *not* a scroll — the instrumented run proves no
scroll is issued — it is rows **above** the viewport changing height or being
merged away as tool calls complete (two rows measurably disappeared between
samples). That is transcript churn, a smaller and separate issue from this one.

## Bugs

- Fixed: `isAtBottom` was latched true by a `LazyVStack` anchor's `onAppear`
  firing off-screen, so every arriving message scrolled a reader in history
  toward the newest end — −146 pt per message.
- Fixed: `.scrollPosition(id:)` re-anchored the transcript on every layout
  change; raising the keyboard threw a reader in history 407 pt off the top.
- Fixed: no bottom re-pin on keyboard show/hide, so the newest message went
  behind the composer for a bottom-pinned reader.
- Fixed: `SessionStore.lastError` had ~20 writers and no reader.
- Fixed: `run(_:for:_:)` and `interrupt` returned silently on a host-routing
  miss, so the action never left the phone and left no trace anywhere.

## Not fixed — B1, laggy scroll / jumps ahead (device)

Not attempted this pass (B2 was prioritised). Two concrete leads found while
reading, both unmeasured:

1. `Components.TextBubble` does per-body-evaluation work on every row:
   `media` runs `MediaScanner.scan(message.text)`, and `prose` / `displayText`
   **compile an `NSRegularExpression` per media ref** — inside `body`, so it
   re-runs on every SwiftUI update, for every visible cell.
2. `SessionDetailView.messageStableIDs` rebuilds a `[String]` of the *whole*
   transcript (client cap 5,000) on every body evaluation, purely to feed
   `.onChange`, which then compares the whole array.

Also observed: a single tool-output cell measured **2,858 pt tall**, which
`LazyVStack` must place on every scroll update.

The `.scrollPosition(id:)` removal may itself help B1 — continuous re-anchoring
against rows whose heights settle asynchronously (images, markdown) is a
plausible source of "jumps ahead, doesn't follow the finger", and it would show
up worse on device. That is a hypothesis, not a measured result.

## Investigation Log

### Reading pass — before any change

Suspect ranked first: `SessionDetailView.transcript` applies
`.scrollPosition(id: $scrollPositionID)` **permanently**, over a
`.scrollTargetLayout()` `LazyVStack`, while the composer hangs off
`.safeAreaInset(edge: .bottom)`.

`scrollPosition(id:)` is a two-way binding: SwiftUI writes the identity of the
view at the anchor back into it as the user scrolls, and re-derives the content
offset to keep that view at the anchor whenever the layout changes. The anchor
here is unspecified, i.e. the **top** edge.

The scroll-anchor feature only needs that enforcement inside `extendWindow()`'s
transaction (that doc's Implementation Details say exactly this: "identity-backed
scroll position, updated atomically with the render-window expansion"). Leaving
it enforcing for the whole lifetime of the view means every layout change
re-anchors the top-most row to the top of the viewport:

- The keyboard raising shrinks the scroll viewport by ~336pt. Pinning the
  previously-top-most row to the top instead of keeping the bottom pinned pushes
  the newest content below the fold — and when the content below that row is
  shorter than the shrunken viewport, there is nothing to fill the screen. That
  is the reported "transcript scrolled above the viewable area".
- The same mechanism fires for any `safeAreaInset` height change: the pending
  strip appearing, the child-sessions bar appearing, the offline notice.

Second suspect (B1, deferred): per-cell work in `Components.TextBubble` —
`media` runs `MediaScanner.scan` and `prose`/`displayText` compile an
`NSRegularExpression` per media ref, on **every** body evaluation, and
`SessionDetailView.messageStableIDs` rebuilds an `[String]` of the whole
transcript (up to 5,000) on every body evaluation to feed `.onChange`.

Both are hypotheses. Reproduce before fixing.

### Measurements — shipped 1.3.0 build vs fix

All on iPhone 17 Pro / iOS 26.3, real software keyboard, session `01a025c2`.
Frames are accessibility `y` in points. Evidence:
`.claude/evidence/20260822-keyboard-scroll/`.

The software keyboard does **not** appear on a headless simulator — only the
AutoFill accessory bar does, which changes the inset too little to reproduce
anything. `flowdeck simulator open` plus
`defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false`
was required before the bug would show at all.

**Case (a) — pinned at the newest message, shipped build:**

| | before focus | after keyboard |
|---|---|---|
| newest message | y=428…655 | y=428…655 (**unmoved**) |
| composer | y=746 | y=445 |

The composer rose 301 pt over content that did not move, so the message being
replied to ended up behind the keyboard. (`05-kbd-up.png`)

**Case (b) — scrolled up in history, shipped build:**

| row | before focus | after keyboard | delta |
|---|---|---|---|
| "Once it verifies the fix I'll report back…" | y=128 | y=−279 | **−407 pt** |

The row the reader was on left the top of the screen. This is the reported
"transcript disappears / scrolls above the viewable area".

**Disconfirming test.** Removing `.scrollPosition(id:)` alone and repeating the
identical gesture: every row unmoved (−358, −290, 111 → identical). Case (b) is
caused by `.scrollPosition(id:)`. But case (a) was **unchanged** by that removal
— the newest message still sat behind the keyboard — which is what established
that these are two separate defects rather than one.

**After both fixes:**

| criterion | measurement |
|---|---|
| SC1 | last row 671→370 and composer 746→445 — both exactly −301, gap preserved at 75 pt |
| SC1 (typing) | last row stays at 370 while typing |
| SC2 | rows at −319, −250 identical before and after focus (**0 pt**) |
| SC4 | 370→671 and 445→746 on dismiss — exact return |
