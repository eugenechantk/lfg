# Feature: user-bubble-night-colors

## User Story

As Eugene reading lfg on his phone in dark mode at night, I want my own message
bubbles to be a calmer blue with off-white text, so the bubble stops glaring
against the black transcript.

## User Flow

1. Open any session on the phone with the system in dark mode.
2. My messages show in a Soft blue bubble with the same off-white text as the
   assistant's prose.
3. In light mode nothing changes.

Design: LFG UI Map canvas, Sessions redesign page, row "User bubble at night"
(2026-10-16). Eugene picked **Soft blue** (`bub-soft`, fill #355C8F) and asked for
the off-white the current designs already use (#F2F2F7, the S2 prose ink)
instead of the board's #E0E9F4.

## Success Criteria

- [x] SC1: In dark mode a sent user bubble fills with #355C8F (was #0A6EE0). —
  **Verify by:** pixel-sample the bubble in a simulator screenshot of
  `LFG_S2_VIEW_FIXTURE=working`.
- [x] SC2: In dark mode the bubble text is #F2F2F7 (was #FFFFFF). — **Verify by:**
  the brightest text pixel inside the bubble in the same screenshot is ≈ #F2F2F7,
  not #FFFFFF.
- [ ] SC3: An optimistic (just-sent) bubble uses the same fill and text, so it
  does not change color when the real turn arrives. — **Verify by:** code review of
  `OptimisticUserBubble` (both read the same tokens) + one send in the simulator.
- [x] SC4: Light mode keeps #0A6EE0 and white. — **Verify by:** pixel-sample the
  same fixture in light mode.
- [x] SC5: The Send button and the blue question/sign-in buttons keep #0A6EE0. —
  **Verify by:** they still read `S2.send`; screenshot of the composer with text.
- [x] SC6: The canvas S2 boards show the new bubble, so the design verifier
  compares against the right colors. — **Verify by:** read the published boards
  back and grep the bubble style.

## Platform & Stack

- **Platform:** iOS (iPhone), SwiftUI + a UIKit text view for bubble text
- **Files:** `ios/LFG/Theme.swift` (`S2` tokens), `ios/LFG/Components.swift`
  (`TextBubble`, `OptimisticUserBubble`), `ios/LFG/SelectableProse.swift`
  (`Palette.onAccent`)

## Steps to Verify

1. Build and run on the iPhone 17 Pro simulator with FlowDeck, dark mode,
   `LFG_S2_LIST_FIXTURE=1 LFG_S2_VIEW_FIXTURE=working`.
2. Screenshot; sample the bubble fill and its brightest text pixel.
3. Repeat in light mode.
4. Independent check with `claude-design-verifier` against the `s2-view` board.

## Implementation Phases

### Phase 1: Tokens and bubble views

- Scope: new `S2.userBubble` / `S2.userBubbleInk` (dark-only change); the two
  bubble views and `Palette.onAccent` read them. Send button untouched.
- Success criteria covered: SC1–SC5
- Verification gate: simulator pixel samples in dark and light.

### Phase 2: Canvas ground truth

- Scope: the S2 boards' user bubble style updated to the new colors; the
  `bubPick` sticky records the decision.
- Success criteria covered: SC6

## Decision Log

- **Text color #F2F2F7, not the board's #E0E9F4.** Eugene asked for the
  off-white the current designs use. #F2F2F7 on #355C8F is 6.1:1.
- **Light mode unchanged.** The request was about night viewing in dark mode.
- **Send button and blue action buttons keep #0A6EE0.** They are controls that
  should stand out; only the bubble moves to the new token.
- **No new Swift test target.** The app target has none; adding one for two
  color constants costs more than it proves. Pixel samples from the simulator
  check the rendered result, which a token unit test would not.
- **`OptimisticUserBubble` moves to the same tokens.** It used
  `Color.accentColor` (iOS 26's #0091FF), so a just-sent bubble already changed
  color when the real turn arrived. It would now jump from bright to soft blue.

## Verification Evidence

Build: `flowdeck run -S 613DD9A0-… --launch-env LFG_S2_VIEW_FIXTURE=working`
(BUILD succeeded 2026-10-16 15:55 UTC, dirty tree incl. other sessions' edits).
Screenshots in `.claude/evidence/user-bubble-night-colors/` (402×874, 1 px/pt).

| SC | Action | Result |
|---|---|---|
| SC1 | `dark-working.png`, bubble box (75,447)–(380,497) pt, most common pixel | `#355C8F` (63% of the box) |
| SC2 | Same box, most common bright pixels | `#E9EBF2`, `#EAECF3`, `#F2F2F7` (glyph core + edge blend). The *max* pixel reads `#FFFFFF`, but that is resampling overshoot: the assistant prose (#F2F2F7 by design) has the same count of pixels above #F2F2F7 (133 vs 138). Control with real white text: the title's dominant bright pixel is `#FFFFFF` (199). So the bubble text is #F2F2F7, not white. The first "brightest pixel" method was wrong for downscaled captures. |
| SC3 | Code: `OptimisticUserBubble` and `TextBubble` both read `S2.userBubble` / `S2.userBubbleInk` | Same tokens. **Live send not exercised**: the fixture session is busy, so a send goes to the queued strip; an optimistic bubble needs an idle session on a real host. |
| SC4 | `light-working.png`, same box | fill `#0A6EE0`, text white (unchanged) |
| SC5 | `dark-composer-send.png`, "Ok" typed, Send button box | `#0A6EE0` with a white arrow (unchanged) |
| SC6 | Artifact `read` of the 6 published boards after version 70 | every user bubble is `background: #355C8F; color: #F2F2F7`; no `#0A6EE0` bubble left (Send buttons keep #0A6EE0) |

Independent check: `claude-design-verifier` vs a fresh `s2-view` board
(sha256 b80f8daa…): **PASS** on fill #355C8F, text #F2F2F7, 20 pt corners,
padding, 318 pt max width, and the Send button #0A6EE0 / white. Only note: the app
uses the continuous iOS corner and the board draws a circular arc (≤1.1 pt at
the tip) — pre-existing, not part of this change. Evidence:
`.claude/evidence/user-bubble-night-colors/verifier/evidence.md`.

Trait switch: the app launched in light mode and was switched to dark while
running; the bubble text re-resolved to #F2F2F7, so the dynamic color works
across a sunset switch, not only at launch.

## Bugs

_None yet._
