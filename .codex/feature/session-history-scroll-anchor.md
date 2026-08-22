# Feature: Stable Session History Scrolling

## User Story

As a user reading an older part of a session transcript, I want background history paging to preserve the content under my eyes so that the app never scrolls ahead independently of my gesture.

## User Flow

1. Open a long session at its newest message.
2. Scroll upward through the rendered transcript.
3. Continue scrolling while older network pages arrive and while the render window reveals buffered messages.
4. The transcript remains under direct user control; older content appears above without snapping back toward newer messages.
5. Leave and reopen any session; the view follows transcript loading and settles on the newest message and composer.

## Success Criteria

- [x] SC1: Prepending older network-history messages does not expand the tail render window or move the visible rows. — **Verify by:** `TranscriptWindowTests` mutation-reconciliation cases plus Simulator recording of a long-session upward scroll while paging.
- [x] SC2: Appending genuinely new live messages while the user reads history preserves the oldest rendered row instead of dropping it. — **Verify by:** `TranscriptWindowTests` append and mixed-mutation cases plus a coordinated real append during the independent Simulator audit.
- [x] SC3: Revealing a buffered earlier page preserves the viewport without a delayed programmatic snap that overrides continued scrolling. — **Verify by:** Simulator recording that crosses at least one earlier-message boundary during a continuous upward gesture.
- [x] SC4: Opening a session and normal at-bottom auto-follow behavior remain unchanged. — **Verify by:** existing Swift tests, FlowDeck build/run, and Simulator check of initial latest-message position.
- [x] SC5: Every session open settles at the newest message as soon as its newest renderable tail arrives, regardless of how long older-page loading continues. Once that tail is placed, a manual scroll-up disables auto-follow as before. — **Verify by:** scroll-policy unit tests plus a FlowDeck recording of leaving and reopening a long session.

## Test Strategy

- Add deterministic LFGCore tests that classify transcript growth by position rather than raw count.
- Add deterministic policy tests proving that opening overrides transient bottom-anchor visibility, then returns control to the user after opening.
- Run the focused `TranscriptWindowTests`, then the complete LFGCore suite.
- Use FlowDeck on the required iPhone 17 Pro simulator and record the interaction because this bug concerns gesture timing and scroll position over time.

## Tests

### Package Unit

- `ios/LFGCore/Tests/LFGCoreTests/TranscriptWindowTests.swift`
  - older-only prepend leaves the window unchanged — SC1
  - newer-only append grows the window by only the appended rows — SC2
  - mixed prepend/append ignores the prepended rows and grows only for appended rows — SC1, SC2
  - missing overlap fails stable without expanding the window — SC1
  - opening follows latest even when the bottom anchor is temporarily absent — SC5
  - after opening, manual scroll-up disables follow-latest — SC5

### Runtime

- Long-session continuous upward-scroll recording — SC1, SC3
- Session-open/latest-message check — SC4
- Leave and reopen a long session, recording through history completion and the final newest-message viewport — SC5

## Implementation Details

- Preserve the existing bounded transcript window and full-history store.
- Reconcile window growth from stable-message identity and ordering, not total-count delta.
- Replace the delayed row-target `scrollTo` restoration during buffered-page reveal with an identity-backed SwiftUI scroll position, updated atomically with the render-window expansion. Preserve active scroll velocity where the OS supports it.
- Keep the open-at-bottom pin active until the first newest-content batch can render, perform a final layout-settled bottom pin, then restore normal user-controlled follow policy while older pages continue loading above the bounded tail.

## Decision Log

- Keep automatic history reveal at the top instead of adding a manual “load earlier” tap. The current interaction is appropriate; the viewport anchoring is the bug.
- Do not alter the in-flight Cloudflare history paging work already present in the working tree.

## Verification Evidence

- SC1 — `cd ios/LFGCore && swift test --filter TranscriptWindowTests`: 14 tests passed, including older-only prepend and mixed prepend/append cases. The 60-second iPhone 17 Pro recording traverses the 643-message idle session from its latest result to its original first prompt without a history-load jump: `.codex/evidence/session-history-scroll-anchor/idle-session-page-boundary.mov`.
- SC2 — The same focused suite passed append-only and mixed-mutation cases; `cd ios/LFGCore && swift test` completed with exit 0 across the full package suite. The independent audit then coordinated a real append while scrolled off-bottom: the same rows retained the same accessibility `y` positions, while the new content was confirmed at the live tail.
- SC3 — FlowDeck interaction crossed multiple 200-message render-window boundaries; each boundary atomically retained the prior first row, preserved velocity on iOS 18+, and issued no delayed scroll. Evidence: `.codex/evidence/session-history-scroll-anchor/idle-session-page-boundary.mov`.
- SC4 — `flowdeck run -S 301FDFF0-C37E-4EDF-BC5D-D67C66513EEC --json` built and launched successfully. The long idle session opened at the latest TestFlight result after its older history settled, and the active 814-message session opened at its live tail. Evidence: `.codex/evidence/session-history-scroll-anchor/open-at-latest.mov`.
- `git diff --check`: passed.
- Independent iOS visual audit: **PASS** for SC1–SC4. Report and reproducible evidence: `.codex/evidence/20260821-004353-ios-visual-audit/evidence.md`.
- SC5 — `TranscriptWindowTests` passed 20/20 and `SessionFocusTests` passed 6/6; the full LFGCore suite passed. The final independent audit opened the active long session at its newest tail, manually scrolled to older content, held that viewport through a full one-minute refresh/activity window, and confirmed neither a bottom snap nor `Opening session…`. Evidence: `.codex/evidence/20260821-194029-ios-visual-audit/evidence.md` and `03-complete-flow.mov`.

## Residual Risks

- Live interaction was exercised on the repository-standard iPhone 17 Pro running iOS 26.3. The iOS 17 fallback uses the same atomic identity anchor but cannot opt into the iOS 18+ velocity-preservation transaction flag.

## Bugs

- Fixed: raw `messages.count` growth conflated top prepends with bottom appends.
- Fixed: the 50 ms delayed `scrollTo(anchor: .top)` could snap against continued user scrolling.
- Fixed during verification: the initial identity-backed version could select the fixed `TOP` marker at a page boundary; the final implementation explicitly targets the first retained message in the same transaction as the window expansion.
- Fixed during SC5 audit: tying the opening pin to the entire multi-page history task blocked manual scrolling for 40+ seconds. The pin now releases as soon as the newest tail is laid out.
- Fixed during SC5 re-audit: a freshly deep-linked detail could lose its session during transient live-list membership churn and fall into `Opening session…`. Focus now snapshots the currently resolved session immediately rather than waiting for a later refresh.
