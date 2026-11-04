# Feature: Chat removal and Files & Links

## User flow

Open a chat's options. Files & Links opens the same resource browser used by Sessions, including older history. On iPad it uses the existing file pane and preview controls.

Hide from this device removes the chat from this client's list. Show hidden chats makes it available again. Hiding preserves the conversation, queued messages and scheduled work.

Delete chat asks for confirmation. It removes this chat's saved messages, instructions, memory and native conversation data on its owning host, and cancels its scheduled tasks. Referenced files outside the chat remain untouched. An active reply or child agent must stop first. An unreachable host produces an actionable error; hiding still works offline.

## Success criteria

- [x] Hide/unhide persists across client restarts without deleting host data or queued messages. Verify with Core tests and native recording.
- [x] Permanent deletion is confirmed, owner-scoped, idempotent, rejects active/stale requests, cancels owned tasks and prevents stale clients from recreating the same chat. Verify backend tests and independent audit.
- [x] Successful deletion clears local cached content and queues, and reconciles other clients through explicit host tombstones. Failed/offline requests preserve the chat. Verify Core tests and native recording.
- [x] Files & Links reuses Session components and indexes the complete paginated conversation. Files and links open against the owning host. Verify paging/resource tests and native iPhone/iPad flows.
- [x] Existing Model/Host controls and ordinary sessions remain intact. Verify builds and focused regression tests.

## Decisions

Hiding is local and reversible. Deletion requires the owning host and an explicit in-app confirmation. Keep minimal identifier tombstones so lost acknowledgments and old client caches cannot resurrect deleted conversations. Retain cancelled scheduled-task audit records under the existing Task primitive.

No real conversations will be deleted during verification. Use isolated temporary stores and fixture hosts. No deployment or commit is part of this request.

## Verification evidence

- Final iOS simulator build and independent native audit: PASS. The iPad audit found a duplicate conversation header in docked mode; removing the forced navbar visibility corrected it. Final build: `chat-removal-files-build-ipad-fix.jsonl`.
- Core baseline: 652 XCTest cases, one skipped, zero failures; 608 Swift Testing cases passed. Updated owner and history checks: all nine ChatRemovalTests passed.
- Backend: 40 tests, 242 assertions across seven chat suites passed. Existing scheduled-task suite: 16 tests, 60 assertions passed. TypeScript check passed.
- Independent backend audit: PASS, 75 tests and 374 assertions, nine focused Core tests, plus an executable owner-safety probe. Four race and ownership defects were fixed and independently rechecked. Report: `.codex/evidence/chat-removal-backend/evidence.md`.
- Native audit: PASS on iPhone and iPad. Recordings prove paginated files and links, previews, source reveal, pane close, composer behavior, hide/unhide persistence, deletion cancellation/success/restart, and offline failure with local hiding. Report: `.codex/evidence/chat-removal-files-native/evidence.md`.
- macOS compilation and 287 desktop feature checks: PASS.
- No commit or deployment.

## Implementation notes

Chat options open the existing AttachmentsSheet on iPhone and FilePaneContainer on iPad. The resource index uses the shared transcript projection. Opening the index fetches all history pages, preserves cached resources if a request fails, and offers Retry.

A minimal host tombstone prevents old clients from recreating a deleted identifier. Cache reconciliation accepts deletion only from the recorded owner. Accepted deletions drain before host shutdown releases the store. The Task store keeps an identifier fence so delayed job creation and stale claims cannot schedule work for deleted chats. Physical cleanup failures remain inaccessible and retry at startup.

Hiding does not stop tasks. Permanent deletion cancels owned tasks and pending notification records. Past notifications and completed external actions cannot be recalled. Cancelled Task audit records remain available under the existing Task primitive. Files outside the chat storage remain untouched.

Owned fixture servers, app receipts, UI sessions and recordings are stopped. Original FlowDeck configuration is preserved. Final source hashes are recorded in `chat-removal-files/source-hashes.json`.

## Release

Committed and pushed in `7dccd94` and `76e525d`. Both host servers are updated. TestFlight 1.4.1 (202611041803) passed canonical verification and is available to internal testers. See `.codex/releases/202611041803.md`.
