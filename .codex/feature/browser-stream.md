# Browser stream

Product tier. Worktree: feature/browser-stream. Scope: minimum live window stream,
mouse and keyboard input, More menu entry, and composer shortcut.

## User flow
Open Browser stream from either session entry point. Pick a Mac window. Watch
live frames, enable control after pausing automation, tap/drag/scroll and type.
Closing/backgrounding disconnects and releases all buttons. The stream routes to
the session's owning host. No automatic agent interruption or resumption in v1.

## Success criteria
- [ ] SC1: ScreenCaptureKit captures a selected window continuously — native helper build and live frame probe.
- [ ] SC2: Mouse click/move/drag/scroll and Unicode text/special keys reach the selected window — protocol tests and controlled native test window.
- [x] SC3: Both session entry points open the same separate view — simulator recording.
- [ ] SC4: Host routing and authentication retained, input bounded/validated/sequenced, stale geometry rejected — Swift and Bun tests.
- [ ] SC5: One controller per host; disconnect/background/focus loss stops input; bounded frames — integration tests and simulator recording.
- [ ] SC6: Permission, unavailable helper, and connection errors have recovery UI — helper probes and simulator evidence.

## Architecture
Native signed Mac helper (ScreenCaptureKit + CGEvent) with private stdio IPC;
Bun WebSocket bridge on existing LFG HTTP host; SwiftUI viewer with UIKit pointer
and keyboard capture. JPEG at up to 10 fps, one frame in flight acknowledged by
the viewer. No transcript, database, recording, clipboard or agent-tool path for
input. Native Mac requires Screen Recording and Accessibility grants.

## Verification evidence

- Mac helper FlowDeck build: PASS (latest build includes desktop lock guard and
  cross-process controller lock).
- iOS FlowDeck build/run on iPhone 17 Pro: PASS. First audit found image overflow
  and low-contrast window titles; fixed intrinsic sizing/clipping and row style.
- Full LFGCore suite: 463 XCTest cases + 113 Swift Testing cases PASS. Four new
  BrowserStream tests cover owning-host URL/authentication, WS conversion,
  protocol decoding and Unicode command payloads. Re-run after protocol update PASS.
- `bun test src/browser-stream.test.ts src/browser-preview.test.ts`: 14 PASS,
  41 assertions, including single owner, validation, sequence rejection,
  disabled control, input-rate bounds and preview regression coverage.
- `bunx tsc --noEmit --pretty false`: PASS. `git diff --check`: PASS.
- Real WebSocket -> native helper -> window list: PASS. Foreign Origin request
  to the verification stream endpoint returned 403.
- Independent audit: both entry points, actual window list, actual Chrome frame,
  Done/reopen and background/reconnect PASS. Final iPhone recheck: fitted image,
  readable titles, no-frame timeout, locked-input rejection, and active-view
  background cleanup PASS. iPad light-mode split view: both entries, centered
  picker, fitted real Chrome frame and closing/reopening PASS. Final independent
  audit is PARTIAL solely for locked-Mac native motion/input acceptance, with no
  unresolved defect in exercised UI paths. Three recordings validated by ffprobe.
- `bun scripts/browser-stream-smoke.ts`: BLOCKED before input; native status
  `desktopAllowsInput:false`, `screenRecording:true`, `accessibility:true`.
- The designated auditor model was unavailable (unsupported gpt-5.4); an
  independent available agent performed the audit instead.

Evidence: `.codex/evidence/browser-stream/`, including audit screenshots/video.
Production port 8766 and service were not changed; verification server uses 9981
and proxies only GET metadata from the live host, never production writes.

## Implementation files

- `desktop/stream-host/`: signed Mac helper, ScreenCaptureKit capture, native
  pointer/text/key delivery, permission setup UI and Debug-only acceptance window.
- `src/browser-stream.ts`: bounded/private stdio bridge, exclusive connection,
  validated input and heartbeat cleanup; registered in `src/commands/serve.ts`.
- `ios/LFG/BrowserStreamView.swift`: picker, fitted live image, mouse/scroll modes,
  secure text composer and special keys, explicit control, reconnect/lifecycle.
- `SessionDetailView.swift`: More menu and composer shortcut to the same sheet.
- `LFGCore/BrowserStream.swift`, `LFGClient.swift`: protocol and authenticated
  owning-host WebSocket request. Tests and native smoke script accompany them.

## Audit fixes

- Fixed UIImageView intrinsic-size overflow using explicit proposed-size handling
  and clipping. Independent recheck screenshot `audit/10-frame-fit-fixed.jpg`.
- Fixed low-contrast picker labels with plain button style and explicit primary
  text. Independent recheck `audit/08-window-titles-fixed.jpg`.
- Locked control request rejects before activation; screenshot
  `audit/11-locked-input-rejected.jpg`. Active-view backgrounding clears the frame
  and connection; screenshot `audit/12-active-view-background-clears.jpg`.

## Remaining acceptance blocker

Mac is locked (verified by waking the display to the login screen and the helper's
status probe). Existing Chrome window capture can return a frame while locked,
but the new disposable test window did not render frames in the initial short
probe. This is not proof of a working interactive stream. Never inject input into
loginwindow. User has been asked to unlock/wake the Mac; run the native smoke
script and complete physical-device/motion checks after that. Input integration
and full continuous-video acceptance remain UNVERIFIED, not passed.

## Decision log

- User narrowed this slice to stream/mouse/keyboard and two entry points; automatic
  agent stop/resume is excluded and explicitly disclosed when enabling control.
- Use authenticated WebSocket JPEG frames at up to 10 fps; one frame in flight,
  per-window generation IDs, bounded input, and no transcript/clipboard pathway.
- Bind to exact owning host; never use the normal closed-session fallback route
  for remote control because that could select a different Mac.
- Frame IDs identify window geometry. On resize, reselect rather than sending
  taps against a potentially letterboxed capture.
- FlowDeck builds in one cwd share result/log locations. Run helper and iOS
  builds sequentially; concurrent builds caused a spurious failed build early on.

## Risks
Foreground Mac interaction; no atomic arbitration with unmanaged agents. User
must pause automation before enabling control. Locked/asleep Mac, Touch ID and
iPhone password-manager integration are outside this minimum. Real permission
and device validation may require user action. No production service restart.

## Handoff

Implementation is ready for review in `feature/browser-stream`; no commit, push,
merge or production deployment performed. Scratch server 9981 stopped after audit.
To finish acceptance: unlock/wake the Mac, run `bun scripts/browser-stream-smoke.ts`,
then exercise the same stream from a physical iPhone (mouse drag/scroll, special
keys, loss of focus and disconnect). The iOS keyboard area has not been driven
through successful native input while this Mac remains locked. Do not label the
feature fully verified until those checks pass.
