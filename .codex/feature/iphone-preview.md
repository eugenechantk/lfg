# iPhone preview in LFG

Status: implemented and verified locally. Independent visual audit PASS. Not released or deployed.

## Behavior

The session More menu opens a native iPhone Preview sheet on that session's host. Opening the sheet lists configured phones without starting capture. The user chooses a phone and turns on Live preview. The host relays fresh JPEG frames through LFG's existing authenticated connection. The local worker token never leaves the Mac.

Turning preview off, closing the sheet, or leaving the foreground clears the image and stops polling. Capture has a three-second lease if a connection drops. Returning to LFG requires an explicit toggle. Preview remains view-only and uses the existing low-rate USB stream.

The iphone-control worker expires images after two seconds without a new JPEG. The relay rejects redirects, oversized frames, invalid images, and non-loopback worker addresses. Control requests serialize per physical phone. The native coordinator waits for pending starts before sending stop, and discards frames from prior viewing generations.

The menu has Session options (Model, Effort, Rename, Fork, Host), Tools (Sign in on iPhone, Files & Links, Terminal, iPhone Preview, Child sessions), and Debug sections. Assign and the inverted transcript spike are removed. Existing availability rules and session lifecycle actions remain intact.

## Acceptance criteria

- [x] The host lists configured phones without exposing tokens or capturing frames.
- [x] Preview requests enforce LFG's Access authentication and only reach validated loopback workers.
- [x] The native sheet starts off, shows live frames, and reports unavailable phones clearly.
- [x] Off, dismiss, background, and failed connections clear stale frames and release capture.
- [x] Late start/frame responses cannot reactivate a disabled preview.
- [x] The More menu uses the requested sections and contains no Assign or inverted spike.
- [x] Backend and Swift tests cover the real transport and lifecycle boundaries.
- [x] A running simulator consumes hihi's real feed; independent visual verification is recorded.

## Boundaries

No commits, push, TestFlight release, production host restart, remote tunnel changes, or account actions are included. Existing concurrent edits are preserved. A separate test listener is used; port 8766 remains reserved for the live host.

## Evidence

- Backend: 17 passing tests, including real local HTTP, authentication failures, worker privacy, frame limits, and stop during pending or failed startup. See `.codex/evidence/iphone-preview/backend-tests.txt`.
- Swift: six passing transport and lifecycle tests. See `.codex/evidence/iphone-preview/swift-tests.txt`.
- Build: FlowDeck iOS build passed; Bun bundled the production host entry point. Logs are in `.codex/evidence/iphone-preview/`.
- TypeScript: full repository `tsc --noEmit` passed after narrowing the toggle JSON payload. The test log is empty because there are no diagnostics.
- Controller: all 34 Python tests passed, including fresh-frame expiry.
- Runtime: a separate listener on 8879 serves the production preview routes. The audit uses a deterministic session fixture because bundled host deduplication routed live sessions back to the old production host. Only the session list and transcript are fixtures; hihi's preview is real. Production port 8766 was not restarted.
- UI evidence: independent PASS on iPhone 17 Pro and iPad Pro 11-inch. The audit showed the grouped menu, live hihi Threads feed, three feed swipes, and capture stopping on off, dismiss, and background. Reopening stayed off. See `.codex/evidence/iphone-preview/audit/20261009-043600-ios-visual-audit/evidence.md`.
- iPad evidence uses FlowDeck recordings and extracted frames because its accessibility snapshot parser failed. Coordinate taps and the rendered UI worked.
- Cleanup: the test listener on 8879 is stopped. The preview worker is stopped, capture is inactive, and prior WDA stream settings were restored. Appium remains available for reuse. No commit, push, TestFlight, or live host restart occurred.
