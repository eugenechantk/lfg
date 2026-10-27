# Live Space in Message

## User story and flow
Watch the Space while its agent works. Open Live Space from Message, watch the desktop, take control, click/type/scroll, then return to chat.

## Success criteria
- [x] SC1: A real Space streams changing desktop video into the iPhone app without manual refresh. Verify with a simulator recording and live host probe.
- [x] SC2: Take control pauses an active agent, confirms it stopped, and enables click, typing, keys and scroll. Verify API guards and recorded browser interaction.
- [x] SC3: Leaving Live Space or backgrounding closes the viewer connection; returning reconnects. Verify host connection counters and a simulator recording.
- [x] SC4: Mac and iPhone build, existing Message behavior passes tests, stream framing rejects malformed input. Verify builds and focused tests.

## Decisions
- Continue in codex/cua-message; no production host changes or release.
- Use Cua's documented RCDP v2 desktop stream, H.264 at up to 15 fps. Relay through the selected LFG host; never expose guest credentials or loopback URLs to the phone.
- View-only video is separate from existing guarded browser controls. Manual control requires an explicit handoff and an idle agent. Returning to chat does not automatically repeat an interrupted prompt.
- Mobbin iPhone and web searches returned regular Grok and voice-agent screens, not Grok Bot's remote-browser flow. Do not claim a visual match.

## Verification evidence
All four criteria passed. Build, test, backend and native evidence appears below.

## Bugs
None yet.

## Implementation
- `src/cua-stream.ts` provides a view-only WebSocket relay with bounded viewers, queued-byte limits, ticket reuse and cleanup.
- `src/cua-message.ts` binds stream access to saved Space records, rejects foreign browser origins, and confirms agent interruption before control.
- `SpaceVideoPacket.swift` validates RCDP packet framing and splits Annex B H.264 units.
- `SpaceLiveView.swift` decodes through Apple's native sample-buffer display layer. Frame arrival does not invalidate SwiftUI. Connection and geometry changes update the view.
- The view closes its connection on navigation and backgrounding. Reconnect is explicit after a transport failure.

## Evidence recorded so far
- Bun: 15 tests, 74 assertions pass (`.codex/evidence/cua-live/backend-tests.log`).
- Swift: 498 tests in 78 suites pass (`.codex/evidence/cua-live/swift-all.log`).
- Mac: build passes; 259 feature checks pass (`mac-build.log`, `mac-tests.log`). Native player screenshot: `.codex/evidence/cua-live/mac-live.png`.
- iPhone: FlowDeck build passes (`.codex/evidence/cua-live/ios-build.log`). Initial compilation exposed a missing public error initializer; fixed and rebuilt successfully.
- Independent backend audit: PASS (`.codex/evidence/cua-live-audit/REPORT.md`). Observed real H.264 keyframes and delta frames, no guest credentials, view-only policy, cleanup and limits.

## Limits
The verified runtime is local, using H.264. Gateway-header authentication, audio, pinch zoom, and hardware-keyboard forwarding remain outside this change. Leaving the viewer stops its network connection; it does not stop the agent or suspend the Space. No automatic retransmission of interrupted tasks.

## Handoff timing correction
The native auditor observed a queued pause during first-run Node/ACP installation. The original five-second wait ended before Cua completed cancellation. LFG now waits up to thirty seconds and keeps input disabled throughout. A regression verifies delayed cancellation sends one interrupt. A warm real-agent run was interrupted within three seconds after tool use; the native auditor observed `turn_ended` and idle status.

The original Claude run retained an old OAuth token and returned 401. The current local Claude sign-in was copied securely into Cua's credential store. A fresh run authenticated and used tools. Automatic token renewal remains outside this feature.

## Final native audit
PASS for SC1–SC4: `.codex/evidence/20261020-232900-ios-visual-audit/evidence.md`.
- Real desktop video changed in the final iPhone build without refresh.
- Final real Claude browser work was interrupted to idle within four seconds; manual input then worked.
- Backgrounding released the viewer slot. Two external viewers could attach while the app was backgrounded; after returning, only one extra viewer could attach, proving reconnection.
- Evidence: `final-live-space-flow.mov` (twenty seconds), `23-final-active-handoff.jpg`, and matching trees in the audit directory.
- All test Spaces are suspended after verification. The isolated host remains available on 127.0.0.1:18967. The Mac test app is closed. No production install, commit or push occurred.
