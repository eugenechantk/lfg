# Bug 019: Inline photo preview does not page to adjacent files

## Status: FIXED — verified 2026-09-27

## Description

Opening a photo from the session transcript and swiping horizontally does not move to the previous or next photo. The current implementation may only supply the tapped file to that viewer entry point, while the Files & Links entry point supplies the complete session file sequence.

## Steps to Reproduce

1. Open a session whose transcript contains at least two photos.
2. Tap one photo's inline file card in the transcript.
3. Swipe left or right across the full-screen photo preview at base zoom.
4. Observe that the selected photo and title do not change.

## Root Cause

`MediaAttachmentsView` presents `FileViewerSheet` with `files: [ref]`, so an inline preview's `FilePreviewSequence` contains exactly one item. The drag gesture runs, but `moveSelection(by:)` rejects both directions because there is no valid destination index.

The gesture implementation itself is working. `AttachmentsSheet` supplies the full session file sequence, and the same left swipe successfully moved from `card-selection screen` to `minting screen` when the viewer was opened from Files & Links.

## Success Criteria

### 1. Inline previews use the full session file order
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** `NEW` — `ios/LFGCore/Tests/LFGCoreTests/MediaRefsTests.swift` → `inlineUsesSessionSequence`

**Simulator verification:**
1. Open the Apple Pay session with adjacent inline cards `card-selection screen` and `minting screen`.
2. Tap `card-selection screen` in the transcript.
3. Swipe left at base zoom.
4. **Expected:** title and image advance to `minting screen`.

### 2. Inline previews page in both directions
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** `EXISTING` — `ios/LFGCore/Tests/LFGCoreTests/MediaRefsTests.swift` → `preservesOrderAndSelection`

**Simulator verification:**
1. Continue from `minting screen` after criterion 1.
2. Swipe right at base zoom.
3. **Expected:** title and image return to `card-selection screen`.

## Investigation Log

### Attempt 1

**Hypothesis:** The TestFlight build contains the paging code, but the transcript entry point initializes the viewer with only the tapped file.

**Changes:** Created this investigation record; no product code changes.

**Result:** Confirmed in source and Simulator. Two adjacent inline photo cards were visible in the Apple Pay session. Opening `card-selection screen` and swiping left left the title and image unchanged. Opening that same file from Files & Links and performing the same swipe moved to `minting screen`.

**Source evidence:**

- `ios/LFG/RichContent.swift:386-391` passes `[ref]` from the inline card.
- `ios/LFG/RichContent.swift:747-765` rejects paging when the requested destination is outside the sequence.
- `ios/LFG/AttachmentsSheet.swift:40-45` passes the complete session file sequence.

**Runtime evidence:**

- `.codex/evidence/bug-019-inline-photo-paging/inline-after-left-swipe.jpg` — inline preview remained on `card-selection screen`.
- `.codex/evidence/bug-019-inline-photo-paging/files-links-before-left-swipe.jpg` — control preview opened from Files & Links on `card-selection screen`.
- `.codex/evidence/bug-019-inline-photo-paging/files-links-after-left-swipe.jpg` — the same left swipe advanced to `minting screen`.
- Navigation replay: `ios/.sim-navigate/photo-paging-diagnosis/20260927-175008-in-lfg-close-the-current-file-preview-re/replay.sh`.

### Attempt 2

**Hypothesis:** The share-sheet changes may have broken gesture recognition globally.

**Changes:** No product code changes.

**Result:** Rejected. The Files & Links control path paged successfully, and the share commit did not alter `pagingGesture` or `moveSelection(by:)`.

### Attempt 3

**Hypothesis:** Supplying the session-wide Files & Links sequence to inline cards will enable the existing pager without changing gesture arbitration.

**Changes:** Added a transcript-version-scoped session file index, exposed it to inline attachment cards through SwiftUI environment state, and added a row-level fallback for unavailable or stale indexes.

**Result:** Focused `FilePreviewSequenceTests` passed (5 tests); the complete LFGCore suite passed (207 tests in 32 suites); FlowDeck build and launch passed. In Simulator, opening inline `card-selection screen`, swiping left, then swiping right produced titles `card-selection screen` → `minting screen` → `card-selection screen`.

**Defensive coverage:** `inlineFallsBackToRowSequence` verifies that an inline preview still opens from its message attachments when the session index is unavailable or does not yet contain the selected file.

**Evidence:** `.codex/evidence/bug-019-inline-photo-paging/inline-paging-fixed.mov` (H.264, 1206×2622, 18.94 seconds).

## Final Summary

Inline transcript cards now use the same session-wide file order as Files & Links, while retaining a safe message-row fallback during initial or stale indexing. The existing base-zoom gesture arbitration is unchanged.

The independent visual audit passed all criteria on iPhone 17 Pro, iOS 26.3. Report: `.codex/evidence/20260927-194900-ios-visual-audit/evidence.md`; complete interaction recording: `07-bidirectional-paging-complete.mov`.
