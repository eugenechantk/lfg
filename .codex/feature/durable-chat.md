# Durable chat sessions

Historical first implementation. The native conversation architecture and current verification are recorded in [native-durable-chat.md](native-durable-chat.md). Its provider persistence and context handling supersede the earlier decisions below.

## User story and flow

Create a lasting conversation, give it standing instructions and private memory, and message it without creating a Space.

Open Message, create a chat, then send and stop turns. Edit instructions and memory in chat settings. Return after app or host restart and continue the same conversation.

## Success criteria

- [x] SC1: Chat identity, instructions, memory, and ordered history survive service restart without Cua. Verify with real temporary-file route tests.
- [x] SC2: Host-side Claude replies with no tools, MCP servers, project instructions, or hooks. Verify launch-policy/parser tests and one real text-only conversation.
- [x] SC3: Serialized turns, stable request receipts, interruption, and restart recovery prevent duplicate work. Verify concurrent and interrupted route tests.
- [x] SC4: Automatic conversation summaries preserve older context while full history remains readable in pages. Private memory and edits affect the next turn. Verify compaction, failure, and isolation tests.
- [x] SC5: Native Mac and iPhone Message provide creation, chat, settings, memory, loading, and errors without desktop controls. Verify core client tests, native builds, and recorded independent simulator audit.
- [x] SC6: Chat uses the shared Session snapshot, status vocabulary, and event journal. Notification observation uses explicit runtime status. Verify snapshot/event/notification tests and native routing.

## Platform and stack

Bun/TypeScript host with atomic JSON files; Foundation client and shared SwiftUI views.

## Decision log

- Continue in the existing `codex/cua-message` worktree. Preserve its desktop prototype and unrelated edits. Do not merge, commit, install on production hosts, or release.
- First runner: Claude Code in text-only print mode, using the host sign-in. Own the canonical conversation in LFG. Do not copy credentials or persist provider sessions.
- A durable chat is a Session with `kind: chat`. Keep terminal discovery and terminal control unchanged; combine snapshots at the host boundary.
- Each chat belongs to one host. Cross-host failover and scheduled task integration are later work.
- Separate editable memory notes from automatic conversation summaries. LFG maintains summaries through the same tool-free runner. Keep all original messages.
- Use native forms and multiline text editors, following HIG Text views and Sheets. Reuse the existing Message destination and keep Space UI outside that destination.
- Keep replies and request receipts in separate turn files, so streaming does not rewrite the entire conversation.

## Verification evidence

- Backend: 15 focused tests, 65 assertions passed. `.codex/feature/durable-chat-backend-tests.txt`.
- Regression: 152 backend, Cua, status, and push tests passed with 430 assertions. `.codex/feature/durable-chat-regression-tests.txt`.
- Independent backend audit: PASS after context re-audit. Eleven independent probes, 76 assertions, plus 85 regressions, 222 assertions. Real killed-process ownership recovery and fake CLI tool rejection passed. `.codex/evidence/durable-chat-backend-audit/REPORT.md`.
- TypeScript: full check passed. `.codex/feature/durable-chat-types.txt`.
- Swift: all 505 tests in 80 suites passed, including the new chat contracts. `.codex/feature/durable-chat-swift-tests.txt`.
- Native: Mac build and 259 feature checks passed. iPhone build and launch passed. `.codex/feature/durable-chat-mac-build.txt`, `durable-chat-mac-tests.txt`, `durable-chat-ios-run.jsonl`.
- Real provider: the isolated HTTP host accepted a durable chat and returned `Memory: Your dog is named Pip.` with state completed. `.codex/evidence/durable-chat/live-first.json`.
- Real restart and summary: two original messages survived service replacement. An automatic summary retained `juniper`; the next reply used edited memory `Miso` and the updated `Remembered:` instruction. All four original messages stayed readable. `.codex/evidence/durable-chat/live-restart-result.json`.
- Real recall regression: the exact native-audit prompts now return `Indigo: Your favorite fruit is mango.` then `Violet: Your favorite fruit is pear.` after editing settings. `.codex/evidence/durable-chat/live-memory-regression.json`.
- Independent native audit: PASS on the final 09:04:35 build. Five exact Sessions row selections reached Ready with retained history in 0.19–0.91 seconds. Message preserved instructions and memory; a new real reply recalled kiwi. Report and 360-second recording: `.codex/evidence/20261023-170515-ios-visual-audit/evidence.md`. Earlier native evidence covers creation, editing, loading, errors, and recovery: `.codex/evidence/20261023-163900-ios-visual-audit/evidence.md`.
- Final native builds: iPhone `.codex/feature/durable-chat-ios-build-model.jsonl` and launch `.codex/evidence/durable-chat/routing-model-run.jsonl` passed. Mac rebuilt after the model change; all 259 checks passed again. Final Message snapshot: `.codex/evidence/durable-chat/mac-message-final.png`.
- Production host on 8766 remains PID 65278. No production install, commit, push, APNs delivery test, or release occurred.

## Bugs

- Fixed during independent audit: recovery now publishes idle instead of leaving a stale busy journal event.
- Fixed during independent audit: exclusive store claims reject competing live hosts before recovery.
- Fixed during independent audit: compaction now bounds the retained tail by size, including one oversized turn.
- Fixed during real summary verification: summarize only supplied conversation material, excluding runtime/account metadata. The repeated real summary contained only the supplied code-word fact.
- Fixed after native audit: memory now enters the request as explicit user-owned context, with updated facts taking precedence over stale assistant claims.
- Native routing diagnosis: lifecycle traces proved a second split-view push sends `disappear` before its first HTTP response, even while the chat remains visible. The first two lifecycle fixes failed the independent audit. Loading now belongs to an observable model with a weak polling task; transient appearance callbacks cannot cancel it. The independent re-audit passed five repeated selections plus a real memory-aware reply. Root navigation uses canonical chat identity.
- Fixed during Mac snapshot verification: list polling restarts when asynchronously loaded hosts change and stops while the view is hidden. Failed host refreshes preserve already-listed chats.
- Push snapshots that omit kind still identify chat sessions through their LFG-owned ID prefix. They cannot expose terminal End controls.

## Navigation evidence

The instrumented 09:00 build loaded the first selection. On selection two, `appear`, `start`, and `disappear` arrived before the task ran; its first request was cancelled. Logs: `.codex/evidence/durable-chat/routing-lifecycle.log`. Replays and screenshots: `.codex/evidence/durable-chat/routing-instrumented/`.

Apple documents that view identity defines state lifetime. The loader now owns work through its observable model rather than transient appearance events. References: [Demystify SwiftUI](https://developer.apple.com/videos/play/wwdc2021/10022/) and [Managing model data](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app).

## Remaining scope

Claude is the first runner. Codex chat, shared project memory, task attachment, cross-host failover, and desktop capabilities remain outside this release. The existing Space prototype remains intact. Production hosts and TestFlight have not changed.
