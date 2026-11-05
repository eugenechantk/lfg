# Share sheet: chats and a distinct send panel (2026-11-05)

Product tier. Follows `.codex/feature/ios-share-sheet.md` (the shipped extension) and the canvas page "Share sheet (Oct 23)".

## Eugene's three reports

1. The preview and the text to send are not set apart from the list. Match the reference share sheet (`.claude/design/share-sheet/reference-whatsapp-share.png`).
2. Sending to a durable chat always fails with "Enter valid a message identifier".
3. Search says "Search sessions" but finds chats too. Search both, and show sessions and chats in their own sections. Chats do not go on top.

## Causes

1. The panel, the cards and the text field all use the same dark grey (`tertiarySystemBackground` ≈ `tertiarySystemGroupedBackground` in dark mode). The reference uses three levels: sheet #161717, cards #242626, panel #424445, and a text field filled with the card colour and outlined.
2. The extension posts the session shape `{text, clientId}` to `/api/sessions/<chat-id>/send`. The chat route needs `{text, requestID}` and answers `{session, turn, duplicate}`, so validation fails before the turn starts. Uploads also used the chat id, which the upload route (UUID only) and the chat route (no upload action) both refuse. A chat that is mid-turn answers 409.
3. The view titles every result "Results" and labels the field "Search sessions".

## Changes

- Panel: its own lighter surface (dark #48484A, light #E5E5EA) with a hairline on top; a full-width preview strip with a flush thumbnail tile and a divider under it; a text field with the list colour as fill and a visible border. Canvas `sh2-*` boards follow the same three levels.
- Chats: send `{text, requestID: share id}` and accept only a turn echoing that id. Upload files under the share id. A chat that is busy (409) or offline keeps the share queued; the app moves queued chat shares into the chat's own queue (same request id) and flushes it, so the message appears as a queued bubble in the chat and sends after the current turn. A chat send is idempotent by request id, so an interrupted chat send may replay safely.
- Search: placeholder "Search sessions and chats". Sections: Recent (no query), Sessions, Chats, in that order.
- Copy: a busy chat's effect line reads "Waits for its current turn"; the queued confirmation for a busy chat says it sends after the turn.

## Success criteria

1. Sharing a link to an idle durable chat sends it; the chat shows the user turn with the exact text.
2. Sharing to a busy chat queues it; opening LFG moves it into the chat's queue and it sends after the turn, once.
3. Search "mad" shows a Sessions section and a Chats section (sessions first) when both match; the field reads "Search sessions and chats".
4. With a session chosen, the panel, the preview strip and the text field are visibly distinct from the list on iPhone and iPad, dark and light.
5. Sessions still send, create and queue exactly as before (existing ShareCaptureTests stay green).

## Verification (2026-11-05, Pro)

- Root cause reproduced on a real scratch `lfg serve` (port 18894, temp `LFG_DATA`, private tmux socket): the old body `{text, clientId}` returns `400 Enter valid a message identifier`, and an upload under a chat id returns `409 This action is not available for a chat session`.
- Unit: `swift test` in LFGCore, 616 Swift Testing tests in 92 suites plus the XCTest cases, exit 0. New tests: chat sections, busy-chat copy, chat request id + upload key, 409 queues, interrupted chat send replays, bad echo stays uncertain, `enqueue` keeps a caller's id once.
- Real extension on iPhone 17 Pro sim (`cc-c48b6a68`), opened from the system share sheet:
  - Search "mad" lists the chat under its own Chats heading; the field reads "Search sessions and chats".
  - Send to the idle chat: the chat's user turn is the exact text with the share id as `requestID` (`355A563F…`), sheet shows Sent.
  - Send while the chat runs a turn: share saved `queued`, `waitsForTurn: true`, no error, sheet closes.
  - App handoff: the share left the spool for the chat queue; after the turn ended the next refresh sent it once (`C4221FE5…`), and a further refresh added no copy (4 user turns, 1 share copy).
  - Panel distinct in dark and light; iPad (`cc-c48b6a68-ipad`, iPad Pro 11-inch M5) form sheet checked in dark.
- Canvas: `sh2-*` boards updated (panel #48484A, outlined field, Sessions/Chats sections), LFG UI Map Version 121.
- Evidence: `.claude/feature/evidence-share-chat-20261105/`.

## Also changed

- The app now flushes the chat queue on every refresh when it holds messages, not only while Chats is on screen. This also helps messages typed into a busy chat.
- The search bar has its own fill (light mode had none against the list).

## Not done

- No commit, TestFlight build or device install.
- A busy chat's share sends only once LFG runs a refresh (the app must open or be running). The server has no chat queue; a server-side queue would remove that wait.

## Follow-ups the same day

- Send is a filled blue capsule (#0A6EE0, white label, 44pt tall), not a text link; Retry and the spinner live in the same button.
- The sheet background is darker (#111113 dark) so the search pill (#3A3A3C) stands out. Cards are pinned to #2C2C2E because `tertiarySystemBackground` lifts to #3A3A3C inside a sheet and matched the pill. Measured in the simulator: background 17, cards 44, pill 58, panel 72 (grey levels), like the reference's 22 / 36 / 64 / 66.
- Canvas `sh2-*` boards follow both changes.
