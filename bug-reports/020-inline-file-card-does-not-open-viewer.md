# Bug 020: Inline file card does not open media viewer

## Status: FIXED — verified 2026-09-27

## Description

After TestFlight build `1.3.0 (202609272000)`, tapping an inline transcript file can fail to present the media viewer. The same committed flow opened successfully in the pre-release Simulator audit, so Release-build behavior and live transcript-index updates must be compared.

## Steps to Reproduce

1. Install or launch build `1.3.0 (202609272000)`.
2. Open a session containing an inline image, video, or document file card.
3. Tap the inline file card.
4. Observe that the full-screen media viewer does not appear.

## Root Cause

`MediaAttachmentsView` owned both the tap state and `.sheet(item:)` inside the transcript's `LazyVStack`. The session-wide preview index introduced an asynchronous environment update that can recreate those lazy rows. When that update overlaps a tap, the row-local `viewing` state is discarded before SwiftUI completes sheet presentation. Once the index settles, the same card opens normally, which is why the failure is intermittent.

## Success Criteria

### 1. Inline viewer presentation survives transcript index updates
- [x] Verified in simulator

Open a media-heavy session and tap an inline card immediately after the transcript appears. The full-screen viewer must present on the tapped file.

### 2. Stable presentation preserves full-session paging
- [x] Verified by existing unit tests
- [x] Verified in simulator

From the inline viewer, swipe to the adjacent file and back. The title and content must follow the selection.

## Investigation Log

### Attempt 1

**Hypothesis:** A Release-only presentation issue or a live update to the session-wide preview sequence is invalidating the inline card's sheet presentation.

**Changes:** Created this investigation record; no product code changes.

**Result:** Runtime reproduction in progress.

### Attempt 2

**Hypothesis:** The failure is caused by row-local sheet state being invalidated while the asynchronous session file index refreshes the lazy transcript.

**Changes:** Reproduced the timing-dependent first-tap failure in Simulator. Moved inline viewer presentation ownership to `SessionDetailView`; transcript rows now send a presentation intent upward and retain their local sheet only as a fallback outside a session.

**Result:** Fixed. The row now emits an open intent to `SessionDetailView`, whose existing sheet router owns the preview for the full presentation lifetime. Standalone transcript fixtures retain the row-local fallback.

### Verification

- Focused `FilePreviewSequenceTests`: 5 passed.
- Full LFGCore suite: 814 passed, 1 optional test skipped.
- FlowDeck Debug build and launch: passed.
- FlowDeck Release build and launch: passed.
- Direct Release recording: `.codex/evidence/bug-020-inline-viewer-presentation/release-inline-first-tap-and-paging.mov`.
- Independent Release visual audit: PASS — `.codex/evidence/20260927-204705-ios-visual-audit/evidence.md`.
- Independent continuous recording: `.codex/evidence/20260927-204705-ios-visual-audit/05-release-search-open-page-back.mov`.

## Final Summary

Inline file cards no longer own sheet state inside lazy transcript rows. The stable session-level sheet router now presents the tapped file, so asynchronous transcript/index updates cannot cancel the viewer, while full-session left/right paging remains intact.
