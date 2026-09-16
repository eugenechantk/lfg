# Feature: Session Scroll Performance

## User Story

As an LFG iOS user, I want the session transcript to scroll smoothly immediately after opening a session so that reviewing the conversation feels responsive.

## User Flow

1. Open a session containing enough transcript content to scroll.
2. Begin scrolling as soon as the session view appears.
3. Continue scrolling through mixed transcript content without visible stalls or delayed gesture response.
4. Tap the message input and begin typing as the software keyboard appears.

## Success Criteria

- [x] SC1: Entering a populated session does not trigger avoidable eager rendering of off-screen transcript rows.
- [x] SC2: Initial and sustained transcript scrolling remain responsive while visible content is rendered.
- [x] SC3: Existing transcript ordering, bottom anchoring, pagination, rich content, and selectable prose behavior remain intact.
- [ ] SC4: The populated-session scroll flow passes independent Simulator performance and visual verification. The visual gate passed and the functional performance flow passed; high-frequency hitch measurement was unavailable in FlowDeck 1.20.2, so the performance gate remains partial.
- [x] SC5: Focusing the message input presents the software keyboard without forcing keyboard-safe-area changes through the transcript's row layout.
- [x] SC6: The composer remains above the keyboard, focused, editable, and visually stable while the transcript keeps its position.
- [x] SC7: Keyboard presentation and dismissal pass independent Simulator visual verification.
- [x] SC8: Sending follows the optimistic user row and its reconciled real turn, including when the composer is focused or the reader has scrolled into history.
- [x] SC9: The transcript's visual bottom follows the raised composer on focus and send, keeping the complete newest and outgoing rows above the input panel without resizing the transcript viewport.
- [x] SC10: With the session idle and keyboard hidden, the newest transcript row rests slightly above the composer and dragging to the newest edge cannot expose additional blank transcript space.
- [ ] SC11: Focusing or dismissing the composer preserves a reader's position in transcript history; keyboard transitions follow newest only when the reader was already at the newest edge, while Send still explicitly returns to the sent message.
- [ ] SC12: The first transcript gesture immediately after entering a populated session has the same continuous, responsive motion as later gestures, without eager-rendering the full transcript.

## Test Strategy

- Use code inspection to identify main-thread render work, eager layout, unstable identity, and broad invalidation in the transcript path.
- Preserve existing deterministic transcript-window tests for ordering, paging, merging, and visible-window behavior.
- Build and run the app in Simulator, record the complete open-and-scroll interaction, and independently audit responsiveness.
- Use a performance trace if code review and interaction recording do not provide enough evidence.

## Tests

- Existing `ios/LFGCore/Tests/LFGCoreTests/TranscriptWindowTests.swift` — guards transcript window and pagination behavior for SC3.
- Existing related LFGCore transcript/message tests — regression coverage for SC3.
- Simulator interaction recording and performance audit — proves SC1, SC2, and SC4 at runtime.
- Simulator focus, type, dismiss, and refocus sequence — proves SC5, SC6, and SC7; keyboard/focus behavior is runtime-only and is not honestly covered by package tests.
- Send-follow policy tests plus the network-free real-detail-view fixture — prove SC8 without steering or polluting a live session.
- Keyboard-bottom-follow policy tests plus focus/send recordings in the populated fixture — prove SC9 across focus, optimistic send, and reconciliation.
- Resting-boundary policy tests plus an idle newest-edge drag recording — prove SC10 without weakening keyboard or send following.
- Reader-intent keyboard policy tests plus middle-of-transcript focus/dismiss, newest-edge focus, and history-send recordings — prove SC11.
- A code-first cold-row audit plus matched first-gesture/later-gesture recordings and timing evidence — prove SC12.

## Implementation Details

- Preserved the existing 200-row transcript window and inverted lazy-stack architecture, which already bounds per-frame row placement for long sessions.
- Optimized `SelectableProseView`'s cold render path:
  - defer the first attributed-string render until SwiftUI supplies a real width instead of rendering once at a 10,000pt scratch width and immediately rebuilding;
  - reuse attributed strings across width-only layout passes for paragraphs, table cells, code blocks, and user bubbles, since only the retained whole-message table renderer bakes width into text attributes;
  - reuse parsed markdown blocks when the legacy whole-message renderer genuinely needs a width-dependent rebuild.
- Optimized `ProseTextView` drawing:
  - removed unconditional display invalidation from `layoutSubviews`, which could turn lazy-row placement during scrolling into repeated TextKit redraws;
  - skip the TextKit fragment enumeration entirely for the shipping per-block MarkdownUI path, where MarkdownUI owns table/code decoration.
- Kept MarkdownUI's original rendering hierarchy, horizontal table/code scrolling, and per-block native text selection unchanged.
- Removed Phase-1 geometry diagnostics from the shipping scroll hot path: `onScrollGeometryChange` now publishes only when the reader crosses the newest-edge boolean boundary, and the session view rejects redundant `isAtBottom` writes.
- Isolated keyboard avoidance to the floating composer on iOS 26:
  - the transcript and composer are sibling layers, so the transcript keeps a full-height viewport while only the composer follows the keyboard safe area;
  - the transcript explicitly ignores the keyboard region without changing its existing container-safe-area treatment;
  - the bottom-chrome probe now measures intrinsic controls before keyboard padding is applied, then adds the stable window inset. Keyboard animation can no longer feed a changing height into the inverted transcript's `LazyVStack` padding;
  - sub-point measurement noise is ignored to avoid redundant view-state invalidation.
- Restored send-follow behavior without returning to a broad transcript-follow loop:
  - sends from history still return to the newest edge;
  - focus reserves the software-keyboard occlusion once and follows the inverted newest sentinel at the real scroll edge;
  - focused sends follow that transcript boundary for both the optimistic user row and the real row after reconciliation, so wrapped bubbles cannot extend behind the composer;
  - keyboard dismissal returns to the same newest edge using the full bottom chrome and ordinary transcript gap;
  - unfocused sends already resting at the newest edge keep the natural offset and avoid a redundant bounce.
- Removed the idle transcript's fake bottom tail:
  - dynamic composer and keyboard clearance now lives in `ScrollView.contentMargins`, outside the transcript row stack;
  - the keyboard-visible margin subtracts the home-indicator inset already owned by the software keyboard;
  - the inverted stack no longer has generic structural-top padding that could be revealed as a second visual-bottom gap;
  - discrete multiline-composer height changes follow the newest edge once when the reader was already there.

## Verification

- FlowDeck Debug build: passed on iPhone 17 Pro, iOS 26.5.
- Focused `SelectableTextTests`: 15/15 passed.
- Full LFGCore suite: 494 XCTest tests plus 144 Swift Testing tests passed with zero failures.
- Independent visual gate: passed immediate, sustained, and reverse scrolling; bottom anchoring; fixed chrome; ordering; table/code horizontal scrolling; user-bubble styling; and native block selection. Evidence: `.codex/evidence/20260913-124700-ios-visual-audit/`.
- Independent functional performance audit: immediate motion was visible in the first retained sample 295 ms after swipe injection; 12/12 sustained/reverse gestures completed in 9.464 seconds without blank viewports, layout jumps, crashes, or displaced chrome. Evidence: `.codex/evidence/session-scroll-performance-perf-audit/`.
- Keyboard runtime flow: FlowDeck successfully navigated, focused `composer.message`, presented the software keyboard, typed a draft, and cleared it without sending. The composer moved from y=730 to y=429 and remained entirely above the keyboard while the transcript and navigation chrome remained populated. Evidence: `.codex/evidence/20260913-session-keyboard-performance/`.
- Send-follow runtime flow: the Debug-only fixture uses the shipping `SessionDetailView` and composer while intercepting network sends locally. A send from history logged the newest-edge jump, pending-row jump, reconciliation, and real-row jump. A software-keyboard run kept the 291-point keyboard visible, cleared the draft, confirmed both row-targeted scrolls, and left the landed `Proof` text at y=359–378 above the composer beginning at y=429. Evidence: `.codex/evidence/20260913-send-follow-regression/`.
- Independent send-follow visual gate: passed. It confirmed the keyboard stayed visible, the optimistic and reconciled targets both ran, the complete landed bubble cleared the composer, and no hang, blank viewport, or rendering disruption appeared.
- Earlier keyboard visual gate: partial. It confirmed the session and focused composer remained intact before keyboard presentation, then FlowDeck's relaunch/accessibility bridge failed before the keyboard-rise/edit/dismiss sequence could run. Evidence: `.codex/evidence/20260913-135341-keyboard-focus-visual-audit/`. The final gate below supersedes this incomplete run.
- Final keyboard-boundary runtime flow: tapping the composer moved its field from y=730 to y=429 while the latest assistant row settled fully above the panel at y≈340–405. Sending an 84-character wrapped draft left the complete user bubble at y≈322–387 above the composer beginning near y=417. Evidence: `.codex/evidence/20260914-transcript-keyboard-follow/final-focus-v3/` and `.codex/evidence/20260914-transcript-keyboard-follow/final-long-send/`.
- Independent final visual gate: passed frame-by-frame review of focus and wrapped Send. It found no overlap, abrupt corrective jump, hang, or blank viewport; the keyboard remained present through Send.
- Independent final performance gate: sustained transcript scrolling passed six Simulator swipes with a populated viewport throughout. The 15.42-second recording proxy had 296 analyzed motion frames, a 12.921 ms average interval, a 38.333 ms maximum, and zero gaps above 50 ms. Keyboard/send main-thread attribution remains partial because FlowDeck's capture bridge failed after reboot and exposes no headless hitch profiler. Evidence: `.codex/evidence/20260915-002423-session-keyboard-send-performance/`.
- Idle-boundary runtime flow: on the final iPhone 17 build, the standard idle row stayed at y=641 before and after a newest-edge drag; the wrapped sent row stayed at y=623 before and after the same drag. Focus and wrapped Send kept both rows fully above the raised composer. Evidence: `ios/.codex/evidence/20260915-idle-bottom-void/`.
- Independent idle-boundary visual gate: passed. It found identical newest-row coordinates before and after edge drags, clear separation above the composer in idle/focused/wrapped-send states, and no blank viewport or disruptive corrective jump in the 8.737-second recording.
- Independent final transition motion review: passed. The 74-frame send window averaged 14.429 ms between frames, peaked at 46.667 ms, and had zero gaps above 50 ms. One 6 px reconciliation adjustment occurred, then the row stayed fixed; idle before/after-drag evidence remained effectively identical. Evidence: `ios/.codex/evidence/20260915-final-transition-independent-review/evidence.md`.
- Idle-boundary regression suite: 31 focused `TranscriptWindowTests` passed; the full LFGCore suite passed 494 XCTest tests plus 144 Swift Testing tests with zero failures.
- Latest TestFlight: version 1.3.0 build 202609150248 passed IPA, processing, train, and internal-testing checks and reached `IN_BETA_TESTING` on 2026-09-15.
- FlowDeck 1.20.2 can record Simulator video but has no hitch profiler, so the evidence proves correct state progression and visual continuity, not 60/120 Hz frame pacing. A physical-device Animation Hitches/Organizer check remains the appropriate post-ship confirmation.

## Residual Risks

- Physical-device frame pacing may differ from Simulator results.
- There is no pre-fix trace for an apples-to-apples hitch-rate comparison, and the installed FlowDeck cannot measure high-frequency frame pacing.
- The connected iPhone is on iOS 26.6, which the installed Xcode cannot target; physical-device runtime verification could not run.
- The app still holds the complete transcript in memory; this fix targets first-entry rendering and scroll-frame work, not fetch size or memory footprint.

## Bugs

- Reported: session scrolling is sluggish immediately after entering the session view.
- Fixed: sending a new message no longer followed the latest user row after the full-height transcript rewrite. See `bug-reports/013-send-no-longer-jumps-to-latest-user-message.md`.
- Fixed: the full-height transcript now repositions its visual bottom above the composer during keyboard focus, dismissal, and wrapped sends. See `bug-reports/014-transcript-bottom-does-not-follow-keyboard-composer.md`.
- Fixed: the idle transcript now keeps one small boundary above the composer without exposing additional blank space at the newest edge. See `bug-reports/015-idle-transcript-has-scrollable-bottom-void.md`.
- In progress: focusing the composer while reading history must preserve that position instead of jumping to newest. See `bug-reports/016-focus-from-history-jumps-to-newest.md`.
