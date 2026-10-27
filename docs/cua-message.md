# Message and Cua Spaces

Message gives an agent a separate Linux desktop on an LFG host. The Mac and iPhone clients use the same API.

## Set up a host

1. Install Docker and start its engine.
2. Install the full Cua Spaces app using the official installer at https://cua.ai/docs/spaces/quickstart. The CLI-only runtime cannot provide persistent-agent homes.
3. Start the daemon supplied by Cua Spaces. LFG prefers the app’s bundled `cua`; set `LFG_CUA_BIN` to override it.
4. Configure the agent's provider key in Cua. Run `cua agent keys --help` for the current commands. Cua also supports provider variables in its daemon environment.
5. Restart the LFG host from this checkout.
6. Open Message, select the host, and create a Space.

For this isolated checkout, the full app lives in `.codex/tools/cua/Applications/Cua Spaces.app`. The adapter detects its bundled CLI automatically. The separately installed MIT CLI remains a fallback for desktop-only operations.

The first image download takes longer than later creations. Space creation can remain in progress after a client disconnects. Refresh the list before creating another.

## Use a Space

- Choose Claude Code or Codex when creating the Space.
- Send a task from Chat. LFG follows Cua's event cursor and preserves the run for follow-ups.
- Open Browser to navigate, inspect the desktop image, click, type, and send Enter or Tab.
- Pause the agent before manual browser input. The API refuses input while the agent still runs or its state is unknown.
- Turn the Space off when finished. Local Spaces also stop after five minutes of confirmed inactivity. Closing Message ends its live view; an active agent keeps working.

The bot's persistent home uses Cua Volume. Stopping a local container releases memory and keeps its files. LFG never deletes the desktop automatically.

Idle cleanup protects active agents, connected live viewers, pending sends and operations with unknown outcomes. Reading chat does not keep an unused desktop running. Browser input resets the idle timer. A failed status check starts a new grace period after recovery.

Turning the Space on restarts its desktop. Its previous agent process ended when the container stopped. The next message starts a fresh run with saved conversation context. Completed replies remain available while the Space is off.

## Authentication and connectors

A local Claude or Codex subscription sign-in is not copied into the desktop automatically. For this acceptance run, the current Claude Code token was handed to Cua’s supported `CLAUDE_CODE_OAUTH_TOKEN` credential entry through stdin. It stays in Cua’s credential store; logs and clients never receive it. This is a copy of the current token, and automatic token renewal is not implemented. The first-message preflight checks Cua's host-level provider readiness. This version expects a Cua-saved provider key or a supported provider variable in the daemon environment. Guest-only interactive sign-ins may still appear missing to that preflight.

Configure email or other website accounts in the Space's browser. The app does not import ChatGPT connectors, copy browser cookies, or provide a connector catalog. Sending real email remains an explicit user task; acceptance checks use public websites only.

Cua's runner auto-approves tools inside its desktop. Message does not yet provide enforced approvals for sending email, purchases, or other account actions. Use accounts appropriate for that access.

## State and recovery

Conversation records live under the LFG data directory in `cua-messages/`. Cua owns desktops and agent execution; LFG owns their names, user messages, run references, and UI state.

Requests use unique message identifiers. A repeated confirmed send does not launch the task again. Unknown delivery leaves the message pending and blocks further sends. A confirmed rejection clears pending so the user can retry later.

After an uncertain operation, inspect Cua's agent list before repeating it. There is no automatic retry or reset of unknown delivery in this version.

## Verification

- Run `bun test src/cua-message.test.ts` for API behavior.
- Run `swift test --package-path ios/LFGCore` for the shared client and core regression suite.
- Build the iPhone app through FlowDeck.
- Build the Mac app through `desktop/build.sh`.

Real acceptance requires creating a desktop, controlling its browser, and obtaining an authenticated agent response plus a follow-up. Mocked tests do not replace the last check.

## Commercial use

Spaces components use FSL-1.1-MIT. Review Cua's commercial policy before offering a hosted or managed product to customers:
https://github.com/trycua/cua/blob/main/legal/COMMERCIAL.md

For local containers, LFG uses Docker stop rather than Cua's suspend operation. Previously paused local Spaces are stopped without resuming their agents. This applies to the standard local desktop and custom image profile. Remote Spaces continue through Cua's own lifecycle and are excluded from local idle cleanup.

Keep Docker Desktop Resource Saver enabled. Once all containers stop, Docker can shut down its idle Linux virtual machine while Desktop remains available. Resource Saver cannot reclaim a paused container's memory.

## Live Space

Open Message, choose a running Space, and select **Live Space**. LFG shows the desktop through Cua's native RCDP v2 stream. It uses H.264 video at up to 15 frames per second. A static desktop can send fewer frames.

Select **Take control** to pause the agent. LFG waits for the agent to stop before enabling input. Tap the video to click. Use the URL field, text field, Enter, Tab, and scroll buttons to operate the browser. Each action checks that the agent is still idle. **Done** returns to watching. Give the agent its next instruction in Chat; interrupted prompts do not repeat automatically.

The viewer closes when you leave Live Space or the app enters the background. Returning opens a fresh connection. **Reconnect** recovers from a lost connection. Leaving the viewer does not stop the Space or its agent. Cua expires an unused media session after its short ticket lifetime, currently 60 seconds.

LFG relays video through the selected host. The phone never receives the guest ticket or guest authentication token. Each Space supports two LFG viewers at once. Slow clients disconnect and reconnect from a keyframe instead of accumulating an unbounded video queue.

This version supports the local H.264 runtime verified here. Spaces that require extra gateway authentication show an error. Audio, microphone forwarding, pinch zoom, and hardware keyboard forwarding are not implemented.

Protocol reference: https://cua.ai/docs/spaces/reference/streams-and-display

## Preinstalled Codex profile

A host can use the custom image and explicit Pro folder mounts by setting `LFG_CUA_PROFILE`. See `infra/cua-codex/README.md` for build and setup. This is opt-in per host; existing Spaces keep their images. The trial currently shares only a temporary test folder.

### Control the live desktop

Open Live Space and select **Take control**. LFG waits for the agent to pause before sending input. On Mac, click the video to focus it, then use the mouse and keyboard. Command shortcuts map to Control in Linux. Move the pointer, click, right-click, drag, or scroll within the video.

On iPhone, **Take control** opens the desktop full screen. Rotate the phone to landscape when you want more width. Pinch to zoom and pan with two fingers. Tap with one finger to click, or drag with one finger to move guest items. Tap with two fingers to right-click. **Fit** restores the whole desktop.

Select **Keyboard** to type into the focused guest field. Tab, Escape and Enter remain available in the control bar. Select Keyboard again to hide it. **Done** returns to watching and restores portrait on iPhone.

**Done** clears pending input and returns to watching. An input already sent can finish. A disconnect also ends control. Send another message in Chat to continue the agent. Input affects the guest desktop; it does not move the Pro's physical pointer.
