# Browser takeover from iOS

Date: 2026-09-11
Status: feasibility and recommended implementation plan; no runtime implementation or device validation yet.

## Recommendation

Add **Take over** to LFG's existing browser preview. Stream the selected Chrome
window from the owning Mac, forward human pointer and keyboard input directly
to that Mac, and explicitly return control to the owning Claude Code or Codex
session. This preserves the actual browser profile, cookies, tabs, and login flow.

Use a native Mac helper with ScreenCaptureKit capture and Core Graphics input.
Start with bounded JPEG frames and a separate input/control WebSocket through
LFG's authenticated host connection. Measure the result before adding WebRTC.
The first delivery target is responsive login assistance, not 60 fps video.

This supports either agent when it operates a visible browser on the LFG host.
Cloud-hosted or headless browsers require their own capture/input adapter.
Transport can be shared; identifying the right browser and stopping/resuming the
agent still require integration work for each provider.

## User flow

1. Agent reaches a login or another step requiring human input.
2. User opens Browser Preview and taps **Take over**.
3. LFG holds session delivery, interrupts an active turn if necessary, and waits
   for confirmed inactivity. A failed or ambiguous interruption does not enable input.
4. User selects/confirms the actual Chrome window from live thumbnails. Existing
   transcript screenshots are not sufficient proof of a live window's identity.
5. LFG foregrounds that window and starts live capture. User can zoom, tap,
   scroll, and open an iOS keyboard with Tab, Enter, Escape, and Backspace controls.
6. Password input goes directly through the control channel to Chrome. It does
   not go through the chat composer, send queue, shell command, or model tool call.
7. **Return to agent** disables input, clears pending input, and sends a short
   continuation such as “I completed sign-in. Inspect the current page and continue.”
8. Lost connection or iOS backgrounding disables input and leaves the agent held
   until explicit recovery. It must not silently resume during a half-finished login.

## Reusable components

| Component | What it supplies | Fit |
| --- | --- | --- |
| [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos) | Native capture of a chosen Mac window with configurable output | Recommended capture source; Apple supplies sample code |
| [Core Graphics CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent) | Mouse, keyboard, and scroll event primitives | Recommended native input building block; requires permission and focus handling |
| [stasel/WebRTC](https://github.com/stasel/WebRTC) | Community distribution of WebRTC binaries for iOS/macOS | Candidate for smoother adaptive video later; select and verify a pinned build |
| [noVNC](https://github.com/novnc/noVNC) + [websockify](https://github.com/novnc/websockify) | Mobile-capable VNC client, mouse/keyboard interaction, WebSocket-to-TCP proxy | Fast alternative prototype in WKWebView; requires a compatible VNC server on the same desktop session |
| [Apache Guacamole](https://guacamole.apache.org/doc/gug/guacamole-architecture.html) | Browser client and remote-desktop gateway | More infrastructure than this Mac/iOS feature needs |

noVNC is the closest ready-made remote-control UI. It is not a browser-only
streaming server: window isolation, agent ownership, handoff, and exact macOS
server compatibility remain our responsibility. Its upstream README lists iOS,
touch gestures, keyboard-related features, and Apple authentication support;
that is not an end-to-end test of this project's Mac setup or WKWebView.

WebRTC supplies media/data transport, not capture permission, remote input,
window selection, or agent arbitration. WebRTC also needs a separately validated
network path (ICE and possibly TURN); the existing HTTPS Cloudflare tunnel does
not by itself establish WebRTC media connectivity.

## Why native window capture

The same local Chrome window is the point of integration for Claude and Codex.
It avoids making a second browser session on the phone and transferring cookies.
It also avoids depending on private vendor-extension internals.

An extension-only design is less suitable for unattended takeover of arbitrary
existing tabs: [Chrome tabCapture](https://developer.chrome.com/docs/extensions/reference/api/tabCapture)
requires user invocation of the extension. A new debugger/CDP integration would
also need explicit coexistence testing with both vendor tools; this proposal
does not assume that a second debugger attachment is safe or impossible.

Native OS input affects the Mac's foreground UI. V1 deliberately foregrounds
the selected browser and allows only one human takeover per Mac. Simultaneous
local use, arbitrary background-tab control, and independent concurrent remote
cursors are outside this first slice. Separate windows can hold login dialogs;
capture must follow an explicitly identified related window or show a picker,
never silently stream a different app.

## Existing LFG seams inspected

- `src/browser-preview.ts`: extracts/stores latest frames for Claude and Codex.
  Frame metadata has session ID, source, timestamp, and frame ID, but no live
  Chrome tab/window identity.
- `src/commands/serve.ts`: browser frame endpoints, terminal WebSocket upgrade,
  and session interrupt endpoint already exist.
- `src/closing.ts`: `interruptAndConfirm` checks terminal activity after Escape.
  This is evidence about the terminal, not proof that every in-flight external
  browser action has stopped.
- `src/sendq.ts`: existing delivery system must gain a takeover hold.
- `ios/LFG/BrowserPreviewCard.swift`: floating preview and full-screen entry
  already exist. These currently show action screenshots rather than a live stream.
- `ios/LFGCore/Sources/LFGCore/LFGClient.swift`: browser frame requests, interrupt,
  and per-host Cloudflare credentials provide integration seams.

The current interrupt endpoint intentionally preserves queued sends. Native
Claude queued work can start following an interruption. Calling that endpoint
alone is therefore not a safe takeover implementation.

The earlier `.codex/brainstorm/live-browser-preview.md` is an action-preview
design; this is a distinct interactive mode. The existing
`.claude/brainstorm/agent-portal-login-from-ios.md` explores cookie transfer;
this proposal completes authentication in the host browser itself.

## Control contract

State progression: `agent → requesting → human → returning → agent`.
Disconnect while in human mode leads to `held/disconnected`, not agent mode.

- A host-owned exclusive lease binds controller, host, session, and chosen window.
- Before enabling input, hold LFG sends and establish provider-specific quiescence,
  including queued native messages and outstanding browser calls. If that cannot
  be established, show the live view read-only and explain the blocked takeover.
- Other managed sessions sharing the target browser must be held or takeover
  refused. An LFG lease alone cannot constrain unmanaged agents/extensions.
- Input carries lease generation, sequence number, and geometry generation.
  Reject stale, duplicated, out-of-order, wrong-owner, or old-layout input.
- Map taps from the displayed image through letterboxing, zoom, Retina scale,
  and current window position. If focus/window identity changes, stop input.
- Release pressed keys/buttons on disconnect and return. Never replay password
  text after reconnect; delivery ambiguity requires user review.
- Reuse host authentication and authorize the control session separately; no
  unauthenticated input socket. Bind the native helper to local authenticated IPC.
- Keep frames/input in memory with bounded latest-frame queues. Exclude takeover
  content from logs, transcript extraction, screenshot history, and crash breadcrumbs.

This keeps LFG from sending secrets to an agent. It does not guarantee that a
website or installed extension cannot observe its own password field, or that
the browser's normal credential storage disappears. Disable screenshot/history
publication from LFG's takeover path, and do not promise global invisibility.

## Delivery plan and verification gates

### 1. Prove the actual login seam

Build a minimal native helper and native iOS viewer: user-selected Chrome window,
capture, tap, scroll, text entry, and disconnect. Start at a configurable 5–10 fps
and approximately 1280-pixel width; these are proposed tuning values, not measured
performance. Drop old frames under backpressure; input must not queue behind video.

Use a controlled login form with a test password, then representative real flows
with the user entering credentials. Verify punctuation, Unicode, keyboard layouts,
secure fields, popups, resizing, focus changes, and iPhone keyboard presentation.
Mac Screen Recording/Accessibility permission setup is required. A locked/asleep
Mac and physical Touch ID requirements are not supported promises.

### 2. Prove safe handoff with both providers

Implement the lease and queue hold with separate Claude/Codex stop/continue adapters.
Test an idle login request, active browser batch, already queued next turn, and
two sessions sharing Chrome. Confirm no competing action during human ownership.
If the official integrations cannot establish quiescence, narrow initial takeover
to a verified idle/manual-handoff state instead of claiming arbitrary interruption.

### 3. Integrate and measure

Add Take over / Return to agent to the existing full-screen preview. Test on a
physical iPhone over both the tailnet and the actual Cloudflare Access route.
[Cloudflare supports WebSockets](https://developers.cloudflare.com/network/websockets/),
but authentication, host routing, reconnect, and real latency remain project tests.

Measure capture-to-display latency, click-to-visible response, bandwidth, CPU,
and memory for a ten-minute session. Initial usability target: typical click
feedback below 300 ms on a good connection, not a guaranteed WAN SLA. Move to
WebRTC if measured video quality/bandwidth requires it.

No additional listener may use reserved LFG port 8766. Existing LFG routes can
be extended; any new listener needs an `lsof` port check first.

## Research verification

Read current repository implementation and official/upstream documentation for
ScreenCaptureKit, Core Graphics, Chrome tabCapture/debugger, noVNC/websockify,
WebRTC packaging, Guacamole, and Cloudflare WebSockets. Anthropic explicitly
documents [manual login/CAPTCHA handoff](https://code.claude.com/docs/en/chrome).

No helper compiled, live browser controlled, permission changed, service started,
credentials entered, or tests run in this feasibility pass. Both-provider
compatibility is an architectural recommendation awaiting the gates above.
