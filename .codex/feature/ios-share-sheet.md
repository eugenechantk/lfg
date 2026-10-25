# Feature: iOS share sheet

## User story and approval

Share a link, selected text, images or files from another app into one LFG session, or a new session, on iPhone and iPad.
Eugene approved Claude session c48b6a68-d3a0-4280-83cf-b5e62f2915e7's list-first v2 design on October 23.
Reference: `.claude/design/share-sheet/design.md`, `gen_v2.py`, and boards `sh2-*` in LFG UI Map version 107.
This is product-tier work. Approval already authorizes implementation. Use one recipient, as shown in the approved design.

## Flow and success criteria

1. The system share sheet offers LFG for URLs, text, images and files.
2. LFG opens on Send to, search, pinned New session, Recent (five most recently messaged), and All sessions. No automatic selection or keyboard.
3. Selecting one session reveals an attachment preview and editable message above a blue Send button. The draft starts with shared text and URLs. Upload paths are appended once.
4. Session rows show their host and state. Send explains current-turn, question-waiting, idle, closed/resume, or offline behavior.
5. New session options select host, folder and agent. Existing sends use the owning host and existing API; no new submission route.
6. The extension shares app host configuration and protected credentials. Old credentials migrate without losing main-app access.
7. Persist shares and attachments before a network mutation. Retry safe offline work from the main app. Never silently replay ambiguous creation or delivery. Acknowledge only a validated host response.
8. A delivered share enters the ordinary server queue/transcript. No duplicate local transcript bubble is inserted.
9. iPhone and iPad support list, search, selection, keyboard, sending, failure and cancellation with stable accessibility IDs.

## Test strategy

Swift Testing covers recipient grouping, live/closed reconciliation, text fidelity, file persistence, leases, upload checkpoints, correct routes, acknowledgement and offline/ambiguous failures.
Simulator recordings cover the real extension invoked from a system share sheet on iPhone and iPad. An independent visual auditor verifies the final build.

## Implementation

Use an App Group for a small JSON configuration/cache and per-share durable files. Reuse LFGClient and the existing Keychain credential adapter. A file lease excludes simultaneous app and extension delivery. Keep the app's existing database and outbox unchanged.

## Verification

PASS. The final app and embedded extension build successfully. The complete core suite has 1,170 passed cases and one optional live-terminal case skipped. The independent final audit passed on iPhone 17 Pro and iPad Pro 11-inch (M5).

Final report: `.codex/evidence/20261023-165104-share-final-audit/evidence.md`.
Supporting initial audit: `.codex/evidence/20261023-151500-ios-visual-audit/evidence.md`.

Runtime proof includes real system share entry, Safari title and URL, text editing, single selection, keyboard-safe layouts, images, PDF, cancellation, visible failure, new-session host/folder/agent options, and offline recovery. A six-second host pause proved that uploads keep the extension open. Two queued test shares each produced exactly one receipt when the fake host returned.

Request receipts: `.codex/evidence/ios-share-sheet/verified-receipts.json`. Test sessions used local fake hosts; production-agent execution was not exercised.

## Residual risks

Signed-device App Group and Keychain provisioning require validation with the distribution profiles before a future release. No release or physical installation is requested.

## Architecture choices

The main app keeps its existing GRDB database and outbox location. The extension uses a small App Group spool with per-job process leases. This avoids a database migration and lets it preserve provider files before the host responds. It still uses the existing upload, send and create routes. The app resumes safe queued jobs from foreground and refresh paths. Ambiguous submissions require review, and queued work older than 24 hours requires an explicit retry.

The shared Keychain entitlement names the main app's original default access group. Existing Cloudflare credentials stay in that group. No secrets enter the shared configuration JSON.

Uploads stream from staged files. This avoids holding large media bodies in the extension's limited memory. A completed upload path is checkpointed before sending the turn.

Safari metadata uses the preprocessing contract and webpage activation key described in [Apple's extension keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/AppExtensionKeys.html). Only the selected text and URL enter the draft; the page title is a preview.

## Tests

`ios/LFGCore/Tests/LFGCoreTests/ShareCaptureTests.swift` has 12 tests covering recent order and search, live owner versus synced closed copies, disk copies and checkpoints, process leases, authenticated request bodies and filenames, original host and client identity, offline/ambiguous outcomes, interrupted creation, rejected acknowledgements, upload reuse, new-session first prompts, and stale queues.

2026-10-23: the complete LFGCore suite passed: 522 Swift Testing tests in 78 suites, plus 649 XCTest cases (one skipped, zero failures). The app plus embedded extension built and launched on the session's iPhone 17 Pro. Native activity-controller entry and a busy-session send reached the local fixture host with the exact draft and client ID. Independent final iPhone/iPad audit passed; see the verification section.

## Future release preparation

The Fastlane extension list includes `LFGShare:com.eugenechan.lfg.Share` alongside the widget. Before a signed-device or TestFlight release, register the extension identifier, enable App Group `group.com.eugenechan.lfg` for the app and share extension, and refresh both provisioning profiles. Both targets share the app's existing Keychain group. This implementation task does not create portal identifiers, regenerate distribution profiles, archive, upload or install on a physical phone.

## Regression fixed during verification

The first dismissal timer observed the temporary queued status written before an online upload. That could close the extension before a slow upload finished. The final view starts its timer only when sending has completed with sent or queued status. The independent delayed-upload recording proves the fix.

## Final workspace state

No commit, push, physical installation, or release was performed. Existing unrelated edits remain intact. Both local fixture servers were stopped after the audit. Evidence files remain on disk.

## UI review canvas

[Implemented share-sheet canvas](ios-share-sheet-ui-canvas/canvas.png) covers 57 native views across iPhone, iPad, light and dark appearances, including errors and pending-share recovery. All checklist entries are captured.

[Manifest](ios-share-sheet-ui-canvas/manifest.json) and [coverage notes](ios-share-sheet-ui-canvas/coverage.md) record the states. Rare states use debug-only test inputs in the same production views, and transient confirmations stay open for screenshots. The capture controls were removed from both simulators after capture.
