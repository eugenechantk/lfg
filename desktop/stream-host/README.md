# LFG Browser Stream host

ScreenCaptureKit window video (JPEG, up to 10 fps) and native mouse/keyboard input.
The helper is a Mac app with a stable bundle identifier and private stdio IPC.
It does not listen on a network port. The Bun LFG server bridges it to the iOS
client through `/api/browser/stream`, using the existing host/Cloudflare route.

## Build

From the repository root:

```sh
(cd desktop/stream-host && xcodegen generate)
flowdeck build -w desktop/stream-host/LFGStreamHost.xcodeproj -s LFGStreamHost -S none -d desktop/stream-host/build
```

The server uses that Debug app binary by default. To install elsewhere, set
`LFG_STREAM_HELPER` to the absolute path to
`LFGStreamHost.app/Contents/MacOS/LFGStreamHost`. Use a stable signing identity
when distributing so macOS permissions survive rebuilds.

Open the built app on the Mac once to grant Screen Recording and Accessibility.
Reopen the iOS stream after granting permissions. Remote connections never open
consent dialogs. The logged-in Mac desktop must be unlocked and awake.

## Use

In a session, choose **Browser Stream** from More or the button above the composer.
Pick a window. Pause any browser automation, then enable **Control**. Touch maps to
mouse down/drag/up; Scroll mode maps vertical swipes to wheel events. A long press
right-clicks. Enter text in the secure input field and tap **Type** to send it;
Tab, Enter, Backspace, Escape, Select all and arrow keys are separate controls.
Text never travels through the agent's chat or shell, and is cleared after sending.

This first slice does not automatically stop or resume Claude/Codex. Both work
because input targets their existing visible Mac browser. One controller per Mac, including across LFG worktrees/servers (native process lock).
Locked/asleep desktops reject input before activating a window. Changing window focus stops control. Resizing a window requires reselecting it.
Closing/backgrounding disconnects; reconnect does not replay input.

## Protocol and limits

Client JSON: `select`, `control`, `pointer`, `scroll`, `text`, `key`, `ack`, `ping`.
Server JSON: `windows`, `selected`, `control`, `frame`, `error`, `pong`.
`frameId` identifies a capture geometry generation (stable while window bounds
are stable), not a recording frame number. Each frame is acknowledged before the
helper emits another. Native capture queue depth is three. Client input queue is
bounded to 64 commands and text to 4096 UTF-8 bytes. Sequence numbers reject replays.
No audio, recording, clipboard synchronization, password-manager integration,
or headless/cloud-browser support. No frame/input persistence.

## Verification

`bun test src/browser-stream.test.ts`
`cd ios/LFGCore && swift test --filter BrowserStreamTests`

A true live test requires native permissions. Missing permission must produce an
explicit error on iOS; it is not a reason to replace capture with demo frames.

After unlocking the Mac, run `bun scripts/browser-stream-smoke.ts` from the repo
root. It checks permissions/desktop state before doing anything, creates its own
disposable native window, verifies frames, a button click, Unicode text, a test
password, and control release, then closes only its own processes. Exit 2 means
blocked by desktop state/permissions; exit 1 means a failed acceptance check.
The lock-state guard reads WindowServer's `CGSSessionScreenIsLocked` property via
public `CGSessionCopyCurrentDictionary`; this property needs regression checking
on major macOS upgrades.
