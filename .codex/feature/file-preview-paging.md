# Feature: File Preview Paging

## User Story

As a user viewing a session file from either the transcript or Files & Links, I can swipe horizontally to the file before or after it without dismissing the full-screen preview.

## User Flow

1. Open a session transcript or its **Files & Links** sheet.
2. Tap any inline file card or row in the **Files** section.
3. The full-screen preview opens on that exact file.
4. Swipe left or right to move through the session files in the same order shown in Files & Links.
5. The title and rendered content update to the selected file. Links are not included.

## Success Criteria

- [x] The tapped file is the initially selected preview.
- [x] Horizontal swipes move through every file in `TranscriptResources.files` order.
- [x] The preview title follows the currently selected file.
- [x] Links never appear in the pager.
- [x] Image pinch/pan/double-tap behavior and file-type rendering remain intact.
- [x] A single-file preview still behaves normally.
- [x] An inline transcript file opens on the tapped file with the full session file sequence.
- [x] Swiping left and right from an inline transcript preview moves through adjacent session files.
- [x] If the session-wide index is not ready or does not contain the tapped file, inline preview falls back to the files in that transcript row.

## Test Strategy

- Swift Testing covers construction of the ordered file-only preview sequence and initial selection.
- Swift Testing covers selecting the session-wide sequence for inline previews and its safe row-level fallback.
- FlowDeck simulator recording covers opening a non-first inline file and swiping backward/forward while observing title/content changes.

## Tests

### Unit

- `ios/LFGCore/Tests/LFGCoreTests/MediaRefsTests.swift`
  - file preview sequence preserves the Files list order and selected file
  - file preview sequence safely falls back when selection is absent
  - inline preview uses the full session sequence when it contains the selected file
  - inline preview falls back to row files when the session index is unavailable or stale

### Runtime

- Open an inline transcript file in Simulator and record horizontal paging to the adjacent session file and back.

## Implementation Details

- Add a small platform-neutral `FilePreviewSequence` value in LFGCore.
- Present the selected file in a gesture-driven pager sourced from `AttachmentsSheet` or the transcript's shared session file index.
- Compute the session file index only when transcript identity changes, then expose it to inline attachment cards through SwiftUI environment state.
- Fall back to the current row's files while the session index is unavailable or stale.
- Page on horizontal swipes at base zoom; preserve image pan gestures while zoomed.
- Construct only the selected renderer so hidden video pages cannot autoplay.

## Residual Risks

- None identified for the requested flow. Direct verification and the independent visual audit both passed on iPhone 17 Pro, iOS 26.3.

## Bugs

- The first native `TabView` implementation also paged during a zoomed image pan. Replaced it with explicit gesture arbitration and re-verified the corrected behavior.
- Bug 019: inline transcript cards supplied only `[ref]`, leaving the pager with no adjacent destination.
