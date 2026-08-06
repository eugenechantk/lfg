# Browser Automation Preview for iOS

Status: revised proposal — arbitrary-tab design

## Recommendation

Keep **Claude in Chrome** and the **Codex/ChatGPT Chrome extension** as the
automation engines. Build an **action-synchronized Browser Preview** in iOS:
after each meaningful browser action, the existing Chrome tool captures the
exact tab it acted on; lfg extracts that image from the owning agent transcript
and pushes it into a floating preview.

This is the only robust v1 design when Claude Code or Codex may use any tab or
window available:

- no persistent or pre-armed tab;
- no assumptions about which Chrome window is frontmost;
- no second debugger/CDP attachment;
- no companion extension required for v1;
- session ownership is inherent because the screenshot is in that session's
  transcript/rollout.

The honest product contract is **a fresh frame after browser actions**, not a
continuous 30 fps video. Smooth, silent capture of arbitrary background tabs is
not available through Chrome's public extension APIs: `tabCapture` requires a
user invocation for each captured target, and `captureVisibleTab` only captures
the active tab and is capped at two calls per second.

- [`chrome.tabCapture`](https://developer.chrome.com/docs/extensions/reference/api/tabCapture)
- [`chrome.tabs.captureVisibleTab`](https://developer.chrome.com/docs/extensions/reference/api/tabs#method-captureVisibleTab)

## Evidence From the Current Tools

The installed browser integrations already expose the frame source lfg needs:

- Claude in Chrome has `computer` screenshot actions with a real `tabId`.
- Claude's `browser_batch` can combine interaction/wait actions and a final
  screenshot in one browser tool call.
- Claude Code writes the screenshot result as a base64 image block and a
  temporary JPEG reference in its JSONL transcript.
- Codex rollouts can carry browser screenshots as `input_image` blocks in
  `custom_tool_call_output`.

Phase 0 must turn these observed formats into versioned fixtures and verify the
current Codex Chrome skill emits a frame consistently after meaningful actions.

## User Story

As an lfg user watching an agent from iPhone or iPad, I want to see the latest
state of the actual signed-in Chrome tab Claude Code or Codex is operating, so I
can catch wrong navigation, blocked login, or broken UI without opening the host
machine.

## User Flow

1. Open a managed Claude Code or Codex session in lfg.
2. The agent uses its existing official Chrome extension and browser skill.
3. The lfg observer skill makes each meaningful browser action/batch finish with
   a screenshot of that action's target tab.
4. The host sees the new image block in the owning session transcript and pushes
   it to iOS without putting it in the event journal.
5. A **Browser Preview** mini-view appears or updates, labelled with its age and
   current page origin when available.
6. Drag, minimize, dismiss, or expand the preview. Tap the session label to
   return to the owning lfg session.
7. Switching tabs naturally changes the next frame because the next screenshot
   targets the new tab. No capture reconfiguration is needed.
8. When browser work stops, the last frame remains marked `Updated … ago` and
   the preview collapses after a short idle period.

## Scope

### V1

- Claude Code using the official Claude in Chrome extension/connector.
- Codex using the official Codex/ChatGPT Chrome extension and Chrome skill.
- Arbitrary controlled tabs and windows in the user's existing Chrome profile.
- Multiple agent sessions, each with an isolated latest frame.
- One pinned floating preview per iOS device.
- Foreground iOS delivery over the existing tailnet connection.
- Action-synchronized frames, including before/after frames for long waits when
  the browser skill determines they are useful.

Claude documents that its extension reads, clicks, navigates, takes screenshots,
groups tabs, and connects to Claude Code. OpenAI recommends its Chrome extension
when Codex needs the user's existing Chrome profile and signed-in state:

- [Claude in Chrome](https://support.claude.com/en/articles/12012173-get-started-with-claude-in-chrome)
- [ChatGPT/Codex browser choices](https://help.openai.com/en/articles/20001277-using-the-built-in-browser-in-the-chatgpt-desktop-app)

### Explicit non-goals

- Replacing vendor Chrome tools with Playwright or an lfg-owned browser.
- Requiring a persistent tab, dedicated window, or pre-armed capture lane.
- Reading or modifying private internals of vendor extensions.
- Attaching lfg to Chrome's debugger/CDP transport.
- Claiming continuous video or a fixed frame rate between agent actions.
- Capturing unrelated browser activity while the agent is not acting.
- Remote browser input from iOS.
- Audio, recording, history playback, or additional screenshot persistence.
- Apple system Picture in Picture or background iOS playback in v1.

## Architecture

```text
managed Claude Code / Codex session
                |
                | official Chrome extension + existing browser skill
                v
      arbitrary controlled Chrome tab/window
                |
                | action/batch ends with screenshot(target tabId)
                v
   Claude JSONL / Codex rollout image tool result
                |
                | session-scoped raw transcript tail
                v
       BrowserFrameExtractor adapters
        claude-in-chrome | codex-chrome
                |
                +---- browser metadata ---- existing /api/events
                |
                +---- latest JPEG frame --- /api/browser/stream WS
                                                |
                                                v
                                       iOS Browser Preview
```

## Observer Skill

Create one shared `lfg-browser-preview` skill, installed for managed Claude Code
and Codex sessions. It coordinates the existing vendor tools; it does not expose
new browser controls.

### Skill rules

- After navigation, click, typing/fill, selection, drag, submit, modal handling,
  or any action that materially changes visible state, capture the target tab.
- Prefer one browser batch containing the action(s) plus the final screenshot,
  rather than adding a separate model round-trip.
- Do not screenshot pure DOM reads, console reads, network inspection, or other
  actions that do not change visible state.
- During a long wait, capture at the beginning and completion; do not poll frames
  through model tool calls merely to simulate video.
- When switching tabs, screenshot the newly targeted tab after the first action.
- Use the vendor tool's actual tab identifier. Never infer the target from the
  currently focused OS window.
- When preview mode is disabled by host setting, add no screenshots beyond what
  the browser workflow already requires.

### Cost control

Screenshots consume tool bandwidth and may enter model context. Preview mode
must therefore be opt-in at the host/session level and avoid redundant frames.
The extractor deduplicates identical images before sending to iOS.

## Frame Extraction

### Claude adapter

Correlate transcript blocks by `tool_use_id`:

1. Recognize `mcp__claude-in-chrome__computer` and
   `mcp__claude-in-chrome__browser_batch` tool uses.
2. Read the target `tabId`, action type, and optional page metadata from input.
3. On the matching `tool_result`, prefer its image block; fall back to the
   reported temporary screenshot path when present.
4. Emit one `BrowserFrame` for the owning Claude session.

### Codex adapter

Correlate rollout `custom_tool_call` and `custom_tool_call_output` blocks:

1. Recognize calls made through the installed Chrome/browser skill.
2. Detect screenshot/image output blocks and their current browser/tab context.
3. Emit the image for the owning Codex thread/session.
4. Treat unknown/new plugin formats as unsupported rather than attaching a frame
   to a guessed session.

Codex's browser plugin call shape is more indirect than Claude's and is the
largest Phase 0 risk. Keep both adapters isolated and fixture-driven so one
vendor format change does not break transcript or session delivery generally.

### Image handling

- Decode base64 once on the host and normalize to a bounded JPEG if needed.
- Maximum dimension approximately 960 px; quality approximately 60.
- Hash the normalized bytes and suppress duplicates per session.
- Keep only the most recent frame and metadata in memory.
- Never insert image bytes or base64 into the journal.
- Do not make an additional persistent copy. Vendor transcripts may already
  persist screenshot results; lfg cannot honestly promise otherwise, but it
  should not increase retention.

## Server State and Protocol

### Metadata

Add a `browser` event to the existing cursor-resumable `/api/events` journal:

```json
{
  "sid": "...",
  "state": "active|idle|closed|unsupported",
  "generation": 8,
  "capturedAt": 1785900000000,
  "origin": "example.com"
}
```

The REST session snapshot includes the current browser descriptor as the
authoritative baseline after app launch/resync. Metadata contains origin only,
not full URL/query/fragment.

### Frames

`WS /api/browser/stream?sessionId=...`

- Server sends a descriptor followed by raw JPEG binary frames.
- WebSocket subscribes to one session and never changes owners implicitly.
- One buffered frame maximum; newest generation wins.
- On connection, send the in-memory latest frame if it is still within the
  configured freshness window.
- After server restart, optionally seed from the last recognized vendor
  transcript screenshot without copying it; otherwise wait for the next action.

### Activity state

- First recognized browser tool use: `active`.
- New screenshot: advance generation and captured time.
- Agent turn ends or no browser action for 15 seconds: `idle`.
- Session closes: `closed` and clear the in-memory frame.
- Recognized browser activity with an unparseable frame format: `unsupported`
  with a diagnostic version string, never a guessed image.

## iOS Experience

Call the feature **Browser Preview**, not Live Video or Picture in Picture.

- Root-owned floating view so a pinned preview survives navigation.
- iPhone default about 160 x 100 pt; iPad about 240 x 150 pt.
- Preserve aspect ratio and letterbox rather than crop.
- Overlay: browser glyph, origin, `Now` / `Updated 4s ago`, expand, minimize,
  and close.
- A subtle pulse occurs only when a new frame arrives; never show a continuous
  `LIVE` indicator while the frame is static.
- Tap to expand; drag to safe corners; minimize to a session-labelled pill.
- Auto-show only for the currently open session. Never replace a pinned preview
  with another session silently.
- Never cover the prompt panel or message composer.
- Collapse after approximately 30 seconds without browser activity; preserve the
  user-dismissed state for the remainder of that agent turn.
- Backgrounding iOS closes the frame WebSocket; foregrounding reconnects it.
- VoiceOver exposes open, minimize, close, and move actions.
- Clear the decoded image when the browser/session descriptor closes.

## Phased Delivery

### Phase 0 — prove vendor frame extraction

- Capture current Claude fixtures for `computer` screenshot and `browser_batch`
  action-plus-screenshot, including arbitrary tab switches.
- Capture current Codex Chrome fixtures showing browser calls and `input_image`
  outputs, including arbitrary tab switches.
- Measure when each transcript/rollout block becomes visible while a turn runs.
- Prove the skill can add a final screenshot without materially changing browser
  behavior or requiring another user interaction.
- Measure screenshot token/context cost for representative ten-action workflows.

Gate: both agents reliably produce a session-owned image within 2 seconds of a
meaningful browser action, regardless of tab/window choice. If Codex cannot meet
the gate, ship Claude support first rather than adding heuristic window capture.

### Phase 1 — host extraction and delivery

- Add vendor-specific BrowserFrameExtractor adapters and fixtures.
- Tail browser tool results alongside the existing transcript journal pump.
- Add latest-frame registry, normalization/deduplication, browser metadata
  events, REST baseline, and binary frame WebSocket.
- Add observer-skill installation/configuration and per-session preview toggle.
- Add version diagnostics for vendor format drift.

Gate: two concurrent sessions using different arbitrary tabs never cross frames;
a slow client cannot grow memory or queues.

### Phase 2 — iOS Browser Preview

- Add lenient browser descriptor/event decoding to LFGCore.
- Add `URLSessionWebSocketTask` frame streaming and latest-generation decode.
- Add root-owned preview controller and SwiftUI overlay.
- Implement pin, snap, minimize, dismiss, expand, reconnect, age labels, and
  foreground lifecycle behavior.
- Add accessibility and keyboard/prompt avoidance.

Gate: FlowDeck verification against real Claude-in-Chrome and Codex-Chrome tasks
that open and switch among arbitrary tabs.

### Phase 3 — quality and optional interpolation

- Tune screenshot cadence and compression from measured workflows.
- Add host diagnostics for missing screenshots and adapter version drift.
- Soak browser-heavy turns for memory, transcript growth, and iOS responsiveness.
- Only if action-synchronized preview feels insufficient, spike a companion
  extension that interpolates the active claimed tab at up to 2 fps. It remains
  an enhancement, not the ownership source.

## Success Criteria

- Claude Code and Codex continue using their official Chrome extensions and the
  user's existing signed-in Chrome profile; Playwright is not involved.
- The agent may create, reuse, switch, or close arbitrary tabs without manual
  capture setup.
- Every meaningful browser mutation produces a correct-session preview frame
  within 2 seconds.
- The UI clearly communicates frame age and never represents a static screenshot
  as continuous live video.
- No browser frame from session A is delivered to session B.
- Browser automation behavior is unchanged except for the deliberate screenshot
  at meaningful visual boundaries.
- Duplicate frames are suppressed and slow clients cannot grow queues.
- lfg adds no persisted copy of browser frames and never journals image bytes,
  capture tokens, full URLs, or page content.
- Ending the session clears its in-memory frame and removes the preview.
- Composer, prompts, and navigation remain reachable with VoiceOver and at all
  supported sizes.

## Verification Plan

### Extractors

- Fixture tests for current Claude and Codex tool-use/result formats.
- Correlation tests for interleaved tool calls, missing results, errors, and
  unknown vendor versions.
- Arbitrary-tab tests proving tool target rather than active OS window determines
  the frame.
- Hash/deduplication and image-bound tests.

### Server

- Unit tests for browser activity transitions and stale cleanup.
- WebSocket latest-frame-wins tests with deliberately slow subscribers.
- Two-session isolation integration test with visibly distinct pages.
- Restart test for no stale session/frame ownership.

### iOS

- LFGCore descriptor/event decoder tests.
- Preview controller tests for generations, foreground ownership, reconnect, and
  stale-frame age.
- FlowDeck UI verification on iPhone 17 Pro for new-frame pulse, age label,
  drag/snap, minimize, expand, prompt/composer avoidance, reconnect, and close.
- Real-seam acceptance with Claude and Codex switching across multiple tabs.

### Performance and cost

- Ten-minute browser workflow measuring host/iOS RSS, image normalization time,
  bandwidth, dropped frames, transcript growth, and model input-token impact.
- Pass: bounded queues/memory, no UI hangs, and an acceptable incremental token
  cost documented before default enablement.

## Likely Files

Shared skill/new:

- `lfg-browser-preview` skill for managed Claude Code and Codex sessions

Server/new:

- `src/browser/frame-types.ts`
- `src/browser/claude-frame-extractor.ts`
- `src/browser/codex-frame-extractor.ts`
- `src/browser/frame-registry.ts`
- vendor transcript fixtures and Bun tests

Server/modified:

- `src/journal-pump.ts`
- `src/journal.ts`
- `src/commands/serve.ts`
- `src/sessions.ts` or session response assembly
- managed session setup/configuration for preview skill availability

iOS/new:

- `ios/LFGCore/Sources/LFGCore/BrowserPreview.swift`
- `ios/LFG/BrowserPreviewController.swift`
- `ios/LFG/BrowserPreviewOverlay.swift`
- matching LFGCore tests

iOS/modified:

- `ios/LFGCore/Sources/LFGCore/Models.swift`
- `ios/LFGCore/Sources/LFGCore/SSEParser.swift`
- `ios/LFGCore/Sources/LFGCore/LFGClient.swift`
- `ios/LFG/SessionStore.swift`
- `ios/LFG/RootView.swift`

## Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| Additional screenshots increase model context/token cost | Screenshot only visual mutations, batch with actions, measure Phase 0, keep preview opt-in. |
| Vendor transcript formats change | Isolated fixture-driven adapters, version diagnostics, fail unsupported rather than guess. |
| Codex browser output does not identify target reliably | Correlate call/result context; Phase 0 gate; ship Claude-first if unresolved. |
| Preview feels too static | Honest age UI; tune meaningful-action cadence; optional active-tab interpolation later. |
| Multiple sessions/tabs cross streams | Transcript identity is ownership boundary; isolation integration tests. |
| Vendor transcript already persists images | Do not add copies; document upstream retention honestly. |
| Tool result arrives only after a long batch | End shorter meaningful batches with screenshots; do not wait for entire task completion. |

## Decision Log

- **No persistent-tab assumption.** Agents may use any available Chrome target.
- **Vendor screenshot result is the ownership boundary.** It is the only source
  that knows both the exact target and the exact agent session without guessing.
- **Action-synchronized preview, not promised video.** Smooth arbitrary-tab
  capture is incompatible with Chrome's public permission model under the stated
  zero-setup requirement.
- **No companion extension in v1.** It cannot silently capture arbitrary
  background tabs and is unnecessary for session-correct action frames.
- **No second debugger attachment.** Protect the vendor automation channel.
- **In-app Browser Preview before system PiP.** System PiP remains a separate
  media/background project.

## Product Position

The feature should be described as:

> See the latest state after every browser action, no matter which Chrome tab
> your agent uses.

It should not be described as continuous live video unless Anthropic/OpenAI
expose a supported observer stream or the user explicitly grants OS/browser
screen-capture permission for each surface.
