# Implemented share-sheet review states

Capture the actual `ShareComposerView` in the native share extension. Debug-only fixture inputs hold uncommon states and transient confirmations for review; they do not redraw the UI or send requests. Use the current production view source for every capture.

## iPhone: core flow and payloads

- Native system share entry.
- List first, nothing selected; Send composer absent.
- Search results and search keyboard.
- No search matches.
- Busy recipient selected: joins current turn.
- Question-waiting recipient selected: waits for the answer.
- Idle recipient selected: starts next turn.
- Closed recipient selected: resumes it.
- Offline recipient selected: queues until host returns.
- Multiline message with keyboard.
- Selected text and source URL.
- Text-only message, without a link preview.
- Two image previews.
- PDF preview.
- Generic file/video preview.
- Empty draft: Send disabled.
- Cancellation returns to source.

## New session

- Pinned New session selected.
- Host/folder/agent options.
- Computer menu.
- Agent menu.
- Folder path editing with keyboard.
- Missing folder: Send disabled.

## Delivery

- Upload/send in progress: spinner and locked controls.
- Busy confirmation: added to current turn.
- Prompt-waiting confirmation.
- Idle confirmation: sent.
- Closed confirmation: resumed.
- New-session confirmation: started.
- Offline confirmation: saved on device.
- Failure with Retry.
- Delivery unconfirmed, automatic retry disabled.

## App recovery

- Pending list with queued, failed and unconfirmed shares.
- Remove confirmation.
- Empty pending list after recovery.

## Setup and availability

- Loading shared content.
- Refreshing session list.
- No sessions yet.
- No configured computer.
- Input could not load.
- All computers offline, cached list retained.

## Variants

- iPhone light: all distinct states above.
- iPhone dark: list, selected, editing, attachments, error and success.
- iPad: native centered form sheet; list, selection, keyboard, options and delivery states.
- iPad dark: representative selected and keyboard states.

Include any unreachable state explicitly as a NOT CAPTURED tile and explain the reason. Link final image and manifest from the feature doc.

## Final canvas

2026-10-23: all 57 planned views captured from the current debug app and embedded extension. The canvas has no missing tiles.

- Canvas: `canvas.png` (4784 x 15784 pixels).
- Manifest: `manifest.json`.
- Actual native `ShareComposerView`, system menus, keyboards and app recovery views; no mockup redraws.
- Debug-only inputs seed recipient, attachment, loading and delivery states. Confirmation dismissal is held for capture.
- The two simulators have their capture control files removed. Original pending-share jobs were restored. UI capture sessions stopped.
- The production share view and model source hashes are recorded in `source-hashes.json`.
- This image verifies visual coverage. Runtime delivery evidence remains in the independent audit linked from the feature doc.
