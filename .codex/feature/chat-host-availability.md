# Chat host availability

## User story and flow

Message stays a usable chat list when any or all hosts are unreachable. Healthy hosts load independently. Returning offline shows saved chats. Creation and sending commit locally even when every host is offline. Transport queues or shows retryable errors; availability never blocks client actions.

## Success criteria

- [x] SC1: A host failure never replaces Message with a disabled/error screen, including an empty list. Verify removal of the error branch, zero-row tests, and native mixed-host/all-offline flows.
- [x] SC2: Healthy hosts publish chats before a slow host finishes. Verify deterministic concurrent-discovery tests and native delayed-host recording.
- [x] SC3: Last successful per-host lists survive offline refresh and app relaunch. Successful empty responses clear stale rows; removed/replaced hosts cannot leak cached rows. Verify persistence/merge tests and native offline relaunch.
- [x] SC4: Create chats locally and compose/send multiple messages with all hosts offline. No network gate, disabled composer or offline creation refusal. Verify local persistence tests and native offline create/send/relaunch.
- [x] SC5: Existing chat identity, private context and request receipts retain their owning host. Verify client regressions and native opening/sending, plus iPad/Mac compilation.

- [x] SC6: Reconnection registers the same client chat ID and delivers queued messages in order, exactly once under response loss and relaunch. Verify backend idempotency, client transport tests and native reconnection receipts.
- [x] SC7: Cached conversations open offline with cached history and an editable composer. Failed messages retain text and expose retry without blocking new composition. Verify client tests and native existing-chat offline flow.
- [x] SC8: One offline chat cannot block delivery to another owner. Client queue corruption is preserved and reported rather than overwritten. Verify isolated concurrency and persistence tests.

## Decisions

- Use an isolated worktree from cc5fdaf. Main has unrelated project/build-guard edits; preserve them. No commit, push, deployment or release is requested in this turn.
- Save only chat data in the local cache, never host authentication headers. Scope cached records by configured host identity and origin; prune removed hosts.
- User clarification supersedes the availability-gated creation approach: create chats on the client first and queue messages durably. Choose a host only when execution becomes possible, and pin it before any create request. Existing chats retain their owner; no automatic takeover is needed for offline interaction.
- Apply the software-development, ios-development, ios-testing, swiftui-ui-patterns and FlowDeck workflows. Independent native verification follows implementation.

## Implementation

The client saves a chat identity, instructions and memory before making any network request. Sending adds a stable request ID to a persistent queue and immediately clears the composer. Cached history stays readable. A failed host changes connection status, never access to Create or Send.

Each chat delivers independently and preserves message order. New chats choose an available compatible host, then save that owner before the first create request. Retries keep the same chat and message IDs. Existing chats stay on their owner. The server returns the original chat for a repeated create ID without resetting context or history.

The workspace saves atomically with protected files and excludes host credentials. An unreadable queue remains untouched. Server startup tolerates an interrupted empty creation, preserves any saved data, and shutdown waits for accepted writes before releasing storage ownership.

## Tests and evidence

- `ChatAvailabilityTests.swift`: seven tests for cache isolation, persistence, authoritative empty lists, concurrent discovery and host selection.
- `ChatWorkspaceTests.swift`: seven tests for offline creation, multiple queued messages, relaunch, FIFO delivery, lost responses, owner pinning, permanent errors, independent chats, corrupt files and early canonical echoes.
- `ChatSessionsTests.swift`: HTTP authentication, settings, history, previews and refusing unstable creation on an older host.
- Full Swift package: 582 tests in 89 suites pass. `chat-host-availability/offline-swift-all.txt`.
- Chat and scheduled-task regressions: 157 tests and 890 assertions pass. `chat-host-availability/offline-backend-regressions.txt`.
- TypeScript checking passes. `.codex/evidence/chat-offline-backend-audit/recheck-typecheck.txt`.
- Independent backend audit passes after fixing partial-creation recovery and shutdown ownership. `.codex/evidence/chat-offline-backend-audit/report.md`.
- iOS and Mac native builds pass through FlowDeck. `chat-host-availability/offline-ios-build.jsonl` and `offline-mac-build.jsonl`.
- Root native self-check: both hosts offline, create a chat with private context, send and see Queued. `chat-host-availability/self-navigation/`.
- Revised independent native audit passes. `.codex/evidence/chat-offline-native-audit/evidence.md` records offline creation, several queued messages, private-context and queue persistence after relaunch, response-loss deduplication, FIFO, rejected-message retry, cached offline transcripts and both iPad orientations.
- Final-binary smoke passes on both devices. A fresh Air row loads while Pro takes 15.002 seconds. The older list-only audit remains historical evidence; it does not substitute for the revised queue recordings.
- The final shared UI reloads model choices from the assigned owner when a local draft syncs to a different host. Both native builds include that correction.

## Boundaries and residual risks

Changes remain in `codex/chat-host-availability`, based on cc5fdaf. No commit, push, deployment or TestFlight release is authorized for this fix. Main's unrelated edits remain untouched.

Queue delivery resumes while the chat feature is active. This does not add iOS background execution or cross-host state replication. A new offline chat needs a host with the client-ID capability before it can sync. Cached history includes pages previously fetched on this client. This phase queues creation and messages; settings edits still use the existing host-backed save flow.

All verification uses isolated temporary stores and fake provider replies. No production state, real model execution or physical push delivery is exercised.

## Final cleanup

Regenerated the canonical Xcode project and moved the temporary app-only scheme into the evidence folder. The worktree's FlowDeck configuration still selects LFG; no user configuration was replaced. Main retains its three original tracked edits. Product source hashes match the audited final builds.

## Nonblocking follow-up

Queued sends currently retry on the existing one-second active-view polling cadence. The native audit observed 267 attempts during a prolonged offline interval. Stable receipts kept canonical messages exactly once. Add retry backoff in a later change to reduce foreground network traffic; no background execution is added here.

Final native evidence uses populated cached lists. The zero-row state is covered by tests, source inspection and the earlier unchanged empty-list capture; no app data was cleared to force it. Temporary fixture servers and both UI capture sessions are now stopped.

## Release authorized in follow-up

On 2026-10-29 the user authorized deployment, a TestFlight build and any necessary server restart. Pro host and desktop are updated. TestFlight 1.4.1 (202610291121) passes all Apple-side checks. Air remains offline; its host and desktop updates are staged. No commit or push was requested or performed. Release receipts: `/Users/eugenechan/dev/personal/lfg/.codex/feature/chat-offline-release-202610291121/release.md`.
