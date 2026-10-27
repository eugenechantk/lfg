# Durable chat UI polish and capability audit

> Superseded capability policy, 25 October 2026: native durable chats now support coding tools, shell, files, MCP and skills. See `durable-chat-tools.md`. Earlier text-only policy verification below is historical.

Product tier. Follow the existing worktree and preserve unrelated changes.

## User story

Make durable chat chrome align with Sessions and Tasks. Use a cross to dismiss creation and show the host's complete compatible model catalog in a dropdown. Explain transcript rendering and worker capabilities from current source.

## Success criteria

- [x] Phone list dock has the same bottom position across Sessions, Tasks and Message. Verify fresh screenshots and measured frames.
- [x] Phone conversation input has the same resting bottom clearance as Sessions, and stays above the keyboard. Verify screenshots and a recorded focus/dismiss flow.
- [x] Conversation options uses the same icon and toolbar footprint as Sessions. Verify adjacent screenshots.
- [x] New chat uses an accessible cross button to close. Verify tap/dismiss.
- [x] New chat uses a dropdown populated from the selected host's compatible model catalog, preserves selection, and sends it on create. Verify catalog/client tests and a recorded fixture flow.
- [x] Document actual transcript and tools/MCP/skills/file capabilities from source. Verify launch arguments and runtime output guards.

## Decisions

Reuse the existing list dock and iOS chrome. Reuse the existing session options glyph. Do not alter transcript rendering or grant tools/files while answering architectural questions. Host catalogs drive model choices; Claude is the compatible provider today. Codex requires another worker adapter; no access expansion was made.

## Verification evidence

Independent audit: `.codex/design/durable-chat-match/evidence/polish-audit/evidence.md`.

- Phone polish-r5: tab frames y794, h48 across Sessions, Tasks and Message; create frames y790, h56.
- Ordinary and durable options frames x336, y66, w48, h36, using the same glyph.
- Both composer panels end at y845, with 28 point bottom clearance. Chat internal controls remain one point above Sessions.
- Focused send control ends y520; keyboard starts y539. Native 13.775 second focus/dismiss recording contains 197 frames at variable cadence (14.3 fps average).
- Cross dismiss and complete compatible Claude catalog verified on phone and iPad. The unchanged r4 creation flow persisted `claude-haiku-4-5`; receipt `07-phone-create-fixture-receipt.json`.
- iPad smoke evidence uses r4; the r5 delta is phone toolbar placement and outer frame only.
- iOS polish-r5 and Mac shared-change builds passed. Eight client and six worker policy tests passed. No fresh Mac UI audit for this polish.

Review manifest: `.codex/design/durable-chat-match/polish-review.json`. Review page: `https://share.eugenechantk.me/durable-chat-design-e2e0ad/`.


## Architecture findings

The durable chat transcript is separate from Sessions. Chat uses ChatMessageRecord, a normal ScrollView/LazyVStack, SwiftUI user text, and direct MarkdownUI assistant rendering. Sessions uses SessionMessage and TranscriptMessageView/TextBubble, with ProseView/native SelectableProseView for contiguous selection, MarkdownUI tables/code, and file/media extraction. Shared MarkdownUI dependency does not mean shared rendering behavior. This change does not switch renderers.

The selected LFG host starts the Claude CLI worker. Its working directory is the chat's private provider directory. Standing instructions and private memory are supplied to that provider conversation. The warm worker idles for three minutes, then exits; a later message resumes the saved provider conversation. Neither tmux nor a Space is required.

Launch policy disables tools, MCP configuration, inherited skills/plugins/hooks and settings. The output parser rejects tools or MCP initialization and attempted tool-use blocks. This is a text-only capability policy, not an OS filesystem sandbox: the worker process still runs as the host user. The model has no file-read/shell tool, although the host process can read/write its own saved chat data. Adding tools or computer files would require explicit scoped capabilities; durability itself does not require a Space or forbid tools.

Source evidence: src/chat-native.ts nativeClaudeArgs/environment/Bun.spawn; src/chat-claude.ts ChatClaudeOutput; src/chat-sessions.ts reply context. Installed CLI help confirms safe-mode disables customizations and --tools empty disables all built-in tools.

## Implementation and current verification

The phone dock uses the same positioned footer as Sessions/Tasks, through the same iOS safe-area bar API. The phone composer uses the session view's resting -6 point inset and 8 point keyboard gap. The options button reuses SessionOptionsGlyph rather than an SF Symbol approximation. New chat uses an accessible xmark and a native Menu containing a checked Picker; its full 44-point row is tappable.

Model choices load from the owning host's authenticated /api/models endpoint. All compatible Claude models appear, with Default and a compatibility fallback for older/offline hosts. Settings preserve an existing model not in the catalog. The composer uses this same catalog. Codex is not offered because there is no Codex durable-chat worker; adding Codex needs a separate worker adapter.

- Red test: the new catalog client test failed because ChatSessionsClient had no models method.
- Eight ChatSessionsTests passed after implementation, including catalog route/authentication and model persistence on create.
- Six Claude/native worker tests passed, including tool/MCP rejection.
- Current iOS build polish-r5 passed; native menu self-check displayed Default and all four advertised Claude models, and full-row activation succeeded.
- Independent phone r5 and iPad r4 audit passed; the report records exact scope and residual one-point internal composer difference.

## Review handoff verification

Updated the existing local-media share without uploading recordings. The live URL returned HTTP 200 and matched the generated local HTML byte-for-byte. At a 402×874 browser viewport, all 12 embedded screenshots loaded, the enlarge dialog opened, the 13.775 second video metadata loaded, and no horizontal overflow occurred. Standalone HTML embeds the screenshots and omits the external video. Source fingerprints are recorded in `evidence/polish-source-sha256.txt`.
