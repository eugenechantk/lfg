# Feature: Transcript history loading indicator

## User Story

As an LFG iOS user opening an idle session, I want to see when older transcript pages are still loading so that a temporarily short transcript is not mistaken for the complete conversation.

## User Flow

1. Open an idle session whose transcript requires multiple backward-history pages.
2. The newest messages appear after the first page.
3. Scroll toward the top while older pages continue loading.
4. A compact spinner at the top says that earlier messages are loading.
5. Older messages arrive without moving the message currently being read.
6. The spinner disappears after the history request completes or stops after a terminal failure.

## Success Criteria

- [x] SC1: While the store is fetching transcript history, the session view exposes a top-edge “Loading earlier messages…” progress indicator with a stable accessibility identifier. — **Verify by:** Swift presentation-state tests plus Simulator accessibility-tree and screenshot evidence.
- [x] SC2: The loading indicator disappears when history loading finishes, including after a terminal request failure. — **Verify by:** Swift presentation-state tests plus Simulator evidence after the load completes.
- [x] SC3: Incrementally prepended history preserves the reader’s visible position and the transcript remains scrollable to its beginning. — **Verify by:** existing `TranscriptWindowTests` plus Simulator interaction evidence from opening and jumping to the start of a long idle transcript.

## Test Strategy

Use package-level Swift tests for the deterministic presentation policy (network loading, locally buffered older rows, and completion) and the existing transcript-window tests for stable extension behavior. Use Simulator runtime evidence for actual SwiftUI rendering, accessibility exposure, and long-running page arrival.

## Tests

### Package unit

- `ios/LFGCore/Tests/LFGCoreTests/TranscriptHistoryPresentationTests.swift`
  - loading network history shows a progress row — SC1
  - completed history with no buffered rows hides the row — SC2
  - buffered rows retain the existing progressive rendering row — SC1, SC3
- `ios/LFGCore/Tests/LFGCoreTests/TranscriptWindowTests.swift`
  - existing extension and growth cases preserve the render window invariants — SC3

### Runtime

- Open a long idle session through the configured host, capture the loading indicator at the transcript top, wait for completion, and scroll to the oldest available turn — SC1, SC2, SC3.

## Implementation Details

- Track active history loads per session in `SessionStore`, including retry time.
- Derive the transcript top-row presentation from the active network load and the local render window.
- Keep the existing local window-extension behavior and stable scroll restoration.
- Use accessibility identifier `transcriptHistoryLoadingIndicator` for the genuine network-loading state.
- `SessionStore` reference-counts overlapping `ensureHistory` calls and clears the visible state with `defer`, covering successful completion, no reachable read host, and terminal retry failure.

## Decision Log

- Keep progressive newest-first pagination. The partial transcript is intentional and materially improves time-to-first-content through Cloudflare; the missing piece is honest loading feedback.
- Put the spinner inside the transcript’s top row, not as a blocking overlay, so already-loaded recent messages remain readable.

## Verification Evidence

- SC1 — `flowdeck test -s LFGCoreTests -S A9A3D469-5D12-4581-8F71-46FE7754324F --only LFGCoreTests/TranscriptHistoryPresentationTests --progress`: 4/4 passed. Runtime reproduction on `Manual motion control generation` (`01a01999-e27f-7c42-938f-15e513e265c1`, 4,029 messages) displayed `Loading earlier messages…`; the live accessibility tree contained `transcriptHistoryLoadingIndicator`. Evidence: `.codex/evidence/20260820-transcript-history-loading/01-loading-earlier-messages.jpg` and `01-loading-tree.json`.
- SC2 — The same runtime load cleared `transcriptHistoryLoadingIndicator` after the backward page walk completed. Evidence: `.codex/evidence/20260820-transcript-history-loading/02-history-loaded.jpg` and `02-loaded-tree.json`. The presentation unit test covers the completed/no-buffered-row state; `defer` owns cleanup for all `ensureHistory` exits.
- SC3 — The complete `LFGCoreTests` suite passed 467/467, including `TranscriptWindowTests`. After loading completed, the transcript's existing jump-to-start gesture reached the original beginning of the 4,029-message session. Evidence: `.codex/evidence/20260820-transcript-history-loading/03-full-history-start.jpg` and `03-full-history-start-tree.json`.
- Build — `flowdeck build` completed successfully for the configured `LFG` Debug scheme.
- Runtime logs — no history-loading errors during the successful reproduction; the only connection failure was the independently configured offline Air host returning HTTP 530.
- Independent visual audit — **PASS**. Report: `.codex/evidence/20260820-142626-ios-visual-audit/evidence.md`. The auditor independently captured the live top-edge spinner and accessibility identifier, its disappearance after paging, and stable jump-to-start behavior through completion.

## Residual Risks

The runtime failure path was not forced against the production host because doing so would require intentionally breaking host connectivity. Its loading-state cleanup is deterministic (`defer`) and the terminal presentation state is unit-tested. The successful multi-page loading transition passed independent Simulator audit.

## Bugs

_None yet._
