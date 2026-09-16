# Feature: Outgoing Message Attachments

## User Story

As an LFG iOS user, I want to attach an image or file when creating a session or messaging an existing session so I can give the agent local artifacts without switching to another client.

## User Flow

1. Open either the new-session screen or an existing session.
2. Tap the composer attachment control and choose Photos & Videos or Files.
3. Pick one or more items and see them appear in the composer tray.
4. Optionally enter text.
5. Tap Send once.
6. The app uploads every attachment, sends one agent turn containing the optional text plus uploaded paths, and shows a visible failure with a retry path if upload or delivery fails.

## Success Criteria

- [x] SC1: Both composer surfaces allow photo/video and arbitrary-file selection and visibly stage picked items. — **Verified by:** FlowDeck recordings of both attachment menus and system pickers; photos visibly staged on both surfaces.
- [x] SC2: An existing session receives an attachment-only message. — **Verified by:** live FlowDeck send showing `IMG_CA136F.jpeg` staged, delivered, and rendered in the transcript; send queue payload contained only the uploaded path.
- [x] SC3: An existing session receives one message containing text plus all staged attachment paths. — **Verified by:** payload assembly tests plus a live text-and-image send whose single send queue entry contained the text followed by the uploaded path.
- [x] SC4: Creating a session with attachments works with or without typed text, and the kickoff reaches the agent as one logical message. — **Verified by:** live attachment-only creation, payload assembly tests for both forms, and the created session's single kickoff payload.
- [x] SC5: Upload failure never silently discards an attachment or degrades a mixed message into text-only; the composer/send state exposes a retryable failure. — **Verified by:** missing-upload rejection test and code-path verification that failed uploads retain outbox sidecars and mark the pending message failed for retry.
- [x] SC6: Existing text-only create and in-session sends continue to work. — **Verified by:** focused tests, successful app build, and the full 122-test LFGCore suite.

## Test Strategy

- Add deterministic tests around the message payload/attachment orchestration seam so attachment-only, mixed, and failure behavior do not depend on SwiftUI or PhotosUI.
- Retain existing LFGCore coverage for filename safety, MIME mapping, outbox sidecars, and upload response decoding.
- Exercise both real SwiftUI composer surfaces and the live host transport in Simulator because picker presentation and send wiring cannot be proven by package tests.

## Tests

- `OutgoingAttachmentMessageTests`: readiness for text, attachments, and mixed drafts; ordered payload assembly; attachment-only assembly; text-only compatibility; missing-upload and empty-message rejection.
- `LFGStoreTests.testAttachmentOnlyOutboxCanStartEmptyThenReceiveUploadedPaths`: verifies an attachment-only outbox row can be durably staged before upload and updated with its uploaded path.

## Implementation Details

- Reuse `MessageComposer` and `AttachmentTray`; do not duplicate picker state between screens.
- Preserve `SessionStore` ownership of sends so delivery outlives either view.
- Treat attachment upload failures as send failures instead of using lossy `try?` behavior.
- Persist attachment sidecars and the draft outbox row before upload, then atomically replace the draft payload with the complete text-plus-path message before delivery.
- Pre-upload new-session attachments under a temporary UUID namespace and include every resulting path in the one `/new` kickoff prompt.

## Decision Log

- Require a single logical kickoff for new-session text plus attachments. Sending text in `/new` and attachments as a second follow-up changes user intent and fails for attachment-only creation.
- Preserve existing user changes in high-traffic session files and keep edits minimal.

## Verification Evidence

- `swift test --filter OutgoingAttachmentMessageTests`: 6 tests passed.
- Focused outbox test: 1 XCTest passed alongside the six payload tests.
- Full `swift test`: 122 tests in 20 suites passed.
- `flowdeck build --json --show-warnings`: succeeded for the LFG scheme on iPhone 17 Pro (iOS 26.3).
- Live FlowDeck verification on simulator `B10B7B3D-3A4C-4D2F-A41A-DB23F069F8D9`:
  - New-session image-only send enabled with no text, created one session, rendered the uploaded image, and the agent read it.
  - Existing-session text-plus-image send produced one delivery and the agent described the selected flower photo.
  - Existing-session image-only send rendered `IMG_CA136F.jpeg`; send queue entry `06932f875afc0f8a` delivered a path-only payload in 463 ms.
  - The Files importer opened from both new-session and existing-session attachment menus.
- Visual artifacts: `.codex/evidence/attachments-self/create-flow.mov`, `create-attachment-staged.png`, `create-text-plus-attachment-staged.png`, `create-file-picker.png`, and `session-attachment-only.png`.

## Residual Risks

- The fresh Simulator's Files provider contained no documents, so arbitrary-file picker presentation was verified live while arbitrary-file payload assembly relies on the same covered attachment pipeline and metadata tests.

## Bugs

- Fixed: online upload errors were discarded by `try?`; attachment-only sends disappeared and mixed sends degraded to text-only.
- Fixed: new-session creation sent typed text through `/new`, then attachments as a separate follow-up; an empty kickoff could not reliably create an attachment-only session.
