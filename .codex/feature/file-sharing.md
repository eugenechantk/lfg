# Feature: File Sharing

## User Story

As a user previewing a session file, I can open the native iOS share sheet for the currently displayed file so the available actions match its real file type.

## User Flow

1. Open a file from the transcript or **Files & Links**.
2. Tap the Share button in the file viewer toolbar.
3. LFG downloads the original file, preserving its filename and extension.
4. The native iOS share sheet opens for that local file.
5. iOS supplies type-appropriate actions, including Save Image/Save Video for supported media and Save to Files for documents.

## Success Criteria

- [x] The full-screen file viewer has an accessible Share button for the currently displayed file.
- [x] Tapping Share prepares the original file rather than the image preview rendition.
- [x] The system share sheet receives a named local file URL, allowing iOS to infer the file type and offer appropriate actions.
- [x] Share preparation has a visible busy state and presents a retryable error if the file cannot be downloaded.
- [x] Paging changes which file is shared without changing existing paging, image zoom/pan, or rendering behavior.
- [x] Temporary exported files are isolated and removed after the share sheet is dismissed.

## Test Strategy

- Swift Testing verifies export filename preservation, byte-for-byte copying, unique isolation, and cleanup.
- Existing LFGCore tests continue to verify that an unsized host file URL addresses the original resource.
- FlowDeck Simulator verification records opening a file, tapping Share, and observing the native activity sheet for the displayed file.

## Tests

### Unit

- `ios/LFGCore/Tests/LFGCoreTests/FileShareExportTests.swift`
  - preserves a safe filename and file contents
  - isolates repeated exports of the same filename
  - sanitizes path-like names and falls back for empty names
  - removes the export directory during cleanup

### Runtime

- Open a fixture file in the full-screen viewer, tap Share, and verify the native share sheet identifies the current filename and exposes system destinations.
- Independent simulator audit: `.codex/evidence/20260927-164046-ios-visual-audit/evidence.md` — PASS for image and video flows.

## Implementation Details

- Add a small LFGCore helper that copies a completed URLSession download into an isolated temporary directory with the intended filename.
- Resolve the share source without an image width parameter, then use `LFGClient.downloadResource` so large files and authenticated hosts work without buffering the whole file in memory.
- Present `UIActivityViewController` with the prepared local file URL and keep the file alive until dismissal.
- Declare add-only Photos usage so iOS can expose Save Image/Save Video activities without granting read access to the library.

## Residual Risks

- Share-extension ordering and third-party destinations vary by device, but iOS 26.3 independently showed Save Image, Save Video, and Save to Files for the corresponding fixtures.
- A failed live-host download was not forced during visual verification; the alert path is implemented but not exercised against a real host outage.

## Bugs

_None yet._
