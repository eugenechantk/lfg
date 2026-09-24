# Feature: File Preview Paging

## User Story

As a user viewing a file from the session's Files & Links sheet, I can swipe horizontally to the file before or after it without dismissing the full-screen preview.

## User Flow

1. Open **Files & Links** from a session.
2. Tap any row in the **Files** section.
3. The full-screen preview opens on that exact file.
4. Swipe left or right to move through the files in the same order shown in the list.
5. The title and rendered content update to the selected file. Links are not included.

## Success Criteria

- [x] The tapped file is the initially selected preview.
- [x] Horizontal swipes move through every file in `TranscriptResources.files` order.
- [x] The preview title follows the currently selected file.
- [x] Links never appear in the pager.
- [x] Image pinch/pan/double-tap behavior and file-type rendering remain intact.
- [x] A single-file preview still behaves normally.

## Test Strategy

- Swift Testing covers construction of the ordered file-only preview sequence and initial selection.
- FlowDeck simulator recording covers opening a non-first file and swiping backward/forward while observing title/content changes.

## Tests

### Unit

- `ios/LFGCore/Tests/LFGCoreTests/MediaRefsTests.swift`
  - file preview sequence preserves the Files list order and selected file
  - file preview sequence safely falls back when selection is absent

### Runtime

- Open Files & Links in Simulator, tap a file, and record horizontal paging through adjacent files.

## Implementation Details

- Add a small platform-neutral `FilePreviewSequence` value in LFGCore.
- Present the selected file in a gesture-driven pager sourced from `AttachmentsSheet`.
- Keep the current single-file call site for transcript attachment cards.
- Page on horizontal swipes at base zoom; preserve image pan gestures while zoomed.
- Construct only the selected renderer so hidden video pages cannot autoplay.

## Residual Risks

- The required independent visual-auditor service could not start because its model is unavailable on this account. Direct FlowDeck simulator verification and recordings passed.

## Bugs

- The first native `TabView` implementation also paged during a zoomed image pan. Replaced it with explicit gesture arbitration and re-verified the corrected behavior.
