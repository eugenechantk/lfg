# Native durable chat

> Superseded capability policy, 25 October 2026: native durable chats now support coding tools, shell, files, MCP and skills. See `durable-chat-tools.md`. Earlier text-only policy verification below is historical.

## User story and flow

Create a lasting chat using Claude Code, with private instructions and memory. Send new messages into its native provider conversation. Leave and return after worker or host restart. No Space, desktop, project setup, or tmux is required.

Message opens the chat list. Create chooses name, host, instructions, and memory. The chat shows a centered title and status, plain assistant responses, blue user bubbles, and the rounded composer from LFG UI Map. Settings edit instructions, memory, and model. Stop interrupts a reply without ending the conversation.

## Success criteria

- [x] SC1: A native conversation ID persists across turns and host replacement. Follow-up requests carry new input rather than reconstructed full history. Verify deterministic adapter/service tests and real provider restart probes.
- [x] SC2: Idle workers accept subsequent messages; stopping or shutting down a worker preserves resumable conversation state. Verify worker lifecycle tests and live idle/resume probes.
- [x] SC3: Instruction and memory edits reach the next native turn, including corrections that conflict with old replies. Verify adapter settings revision tests and real provider recall after edits and restart.
- [x] SC4: Stable request receipts, serialized turns, partial replies, error outcomes, and restart recovery prevent automatic duplicate submission. Verify API, service, crash, and concurrent-request tests.
- [x] SC5: Native workers expose no tools, MCP servers, desktop capability, or terminal controls. Verify launch/config inspection, forbidden-event tests, and real provider tool policy probes.
- [x] SC6: The chat UI follows LFG UI Map's list, centered header/status, user bubbles, plain assistant text, rounded composer, model chip, sheets, and platform layout. Its create/settings/navigation flow contains no Space or desktop controls. Verify Swift contracts, native builds, reference comparison, and recorded independent native audit.
- [x] SC7: Existing chat history and shared Session/status/journal consumers continue to work. Terminal sessions remain first-class. Verify existing regressions, old-record upgrade tests, and repeated Sessions/Message routing.

## Stack and test strategy

Bun/TypeScript host and file store; native CLI protocols over stdin/stdout; shared SwiftUI on iPhone, iPad, and Mac. Use Bun integration tests with real temporary files and fake CLI boundaries, Swift Testing client/presentation contracts, real provider probes, and native recordings.

## Design source

LFG UI Map: https://claude.ai/artifact/F2B1MNbv5oxuscm237M9sD, page Chat & Cua Spaces (Oct 21). Exported source: `/Users/eugenechan/dev/personal/lfg/.claude/design/chat-cua-spaces/`. Reuse chat and platform styling; remove desktop stage, tool steps, accounts, shared folders, Space power/status, and manual controls. Replace Space-specific copy with chat copy. Use native adaptive controls rather than matching web mock-ups pixel for pixel.

## Decisions

- Continue in `codex/cua-message`, preserving the previous durable store and unrelated dirty edits. No commits, production install, or release.
- Keep LFG identity/settings/history projection and native provider identity separate. Save provider identity before accepting streamed output. Keep native provider transcripts.
- Keep workers warm between turns, with idle shutdown allowed. Resume saved conversations after worker restart. A process never defines durable identity.
- Keep settings outside compacted conversation and explicitly apply settings revisions. Verify Claude's prompt-snapshot behavior before relying on resumed system prompts.
- Upgrade earlier LFG-only chat history once into a native conversation; never rebuild it on every turn. Retain all original messages.
- Keep Claude as the first provider, matching the accepted rollout scope and existing implementation. Retain a native adapter interface for Codex; do not present an unverified provider choice.
- Use the existing host authentication. No new provider credentials or external services.

## Verification evidence

- Baseline existing chat tests passed before changes: `.codex/feature/native-chat-baseline.txt`.
- Real native protocol probe: one worker handled two turns, then a new process resumed the same provider ID and recalled willow. `.codex/evidence/native-durable-chat/claude-stream-probe.txt`.
- Real service probe: same provider ID and worker PID across warm turns; changed instructions and mango-to-pear memory applied; replacement service recalled willow and pear using the new Violet prefix. `.codex/evidence/native-durable-chat/live-service-result.json`.
- Backend regressions: 143 tests, 414 assertions passed before independent audit fixes. `.codex/evidence/native-durable-chat/backend-tests.txt`.
- Native and independent audit recheck after fixes: 20 tests, 151 assertions passed. `.codex/evidence/native-durable-chat/native-audit-recheck.txt`.
- Swift: 506 tests in 80 suites passed. `.codex/evidence/native-durable-chat/swift-tests.txt`.
- iPhone build passed at 18:20:42 UTC; launch 5E60C67A succeeded at 18:22:28 UTC. `.codex/evidence/native-durable-chat/ios-build.jsonl`, `ios-run.jsonl`.
- Mac build passed after the shared UI changes. `.codex/evidence/native-durable-chat/mac-build.txt`.
- First phone self-review: correct title/status, blue user bubble, plain assistant Markdown, rounded composer, and no desktop controls. `.codex/evidence/native-durable-chat/navigation/`.

Independent backend final audit: PASS, 19 probes with 172 assertions; 24 focused tests with 118 assertions; TypeScript check passed. The earlier broad audit passed 128 regressions with 346 assertions. Report: `.codex/evidence/native-durable-chat-backend-audit/REPORT.md`.

Independent native UI/reference audit: PASS for the audited iPhone flow. The first recording covers creation, real recall, edited instructions/memory, five Sessions routes, Message, model menu, error recovery, working draft/Stop, and light/dark adaptation. `.codex/evidence/20261024-023033-ios-visual-audit/`.

The final recording verifies the discovery fix on the 18:47:40 build. A fresh empty chat entered the shared SessionStore before its first message. Exact local-title search opened it from Sessions. A real reply applied Amber instructions and cedar memory. Sessions and Message reopens retained that reply and Ready status. `.codex/evidence/20261024-024802-ios-visual-audit/evidence.md`.

The unfiltered Sessions viewport contains many terminal rows, so a scroll-to-ID attempt timed out. Local filtering proves membership and correct routing without waiting for the global terminal search index. Global terminal search warming remains outside this chat change.

## Bugs and remaining risks

- Fixed fake-worker test harness to read Bun.stdin.stream().
- Fixed recovery treating an exited zombie as a live unverifiable process.
- Fixed independent audit: legacy upgrade now imports saved summary and unsummarized tail once. Oversized imports fail explicitly.
- Fixed independent audit: native provider directories remain excluded from terminal discovery even without this process's ID registry.
- Fixed independent audit: failed ps inspection rechecks PID liveness and fails closed for a live worker.
- Fixed native audit: empty-chat creation emits a journal discovery event after persistence. The creator refreshes membership directly. Unknown-session discovery bypasses slow terminal archives. Older snapshots cannot replace newer membership or health.
- Hardened orphan recovery: mismatched argv is followed by a liveness recheck. A vanished process permits cleanup; a live unknown process remains protected.
- Final native membership retest passed. Production/APNs delivery are outside this local implementation.

## UI adaptation

The text-only primitive has one active turn per chat. Typing during a reply keeps a draft; Stop remains available until that reply ends. The UI does not show the desktop, tool steps, approval panels, file attachments, or queued execution controls. The app uses a sidebar plus chat on Mac and regular-width iPad; the phone uses push navigation. Dark and light appearance adapt through native colors. The user bubble keeps the selected UI Map blue.

## Final build and regression checks

- Final iPhone build passed at 18:47:40 UTC. `.codex/evidence/native-durable-chat/ios-build-final.jsonl`. An earlier incremental build failed because source signatures changed during compilation; the frozen-source rebuild passed.
- Final Mac build passed. `.codex/evidence/native-durable-chat/mac-build-final.txt`. Its feature CLI passed all 259 checks again. `.codex/evidence/native-durable-chat/mac-final-checks.txt`.
- Chat, journal, and notification regressions passed: 104 tests, 307 assertions. `.codex/evidence/native-durable-chat/final-chat-tests.txt`.
- Actual own-window Mac capture confirms the dark split layout and native chat list. `.codex/evidence/native-durable-chat/mac-background.png`. AX inspection did not expose the command-line snapshot harness, so Mac detail interaction is not independently verified.
- The independent backend report preserves one transient crash fixture identity refusal. The focused recheck and ten crash-only repeats passed. Its original cause remains unknown. A deterministic probe verifies the additional exit-race hardening without weakening the live-PID identity check.
- Recovery before the provider's first initialization acknowledgment, disk failure, and semantic provider compaction are not independently fault-injected.
- Production host on 8766 remains unchanged. All runtime probes used private stores; UI acceptance used port 18974. The isolated 18974 host was stopped gracefully after the audit; its saved chats and evidence remain. No commits, push, production installation, or TestFlight release.

## Verification limits

All success criteria have evidence for this local implementation. The Mac build and actual own-window list capture passed; Mac detail interactions were not independently automated. The regular-width iPad layout shares the compiled split implementation but was not separately runtime-audited. Mac off-screen cacheDisplay evidence was rejected because it cannot render native glass and sidebar correctly. The accepted Mac image uses an actual window capture. Real APNs delivery and a production rollout remain unverified.

## Comprehensive screenshot review — 24 October 2026

The screenshot canvas supersedes the earlier Mac detail and iPad visual-capture limits for reviewing native UI. It contains 122 screenshots across iPhone, iPad, Mac, and labeled real-provider continuity evidence. Controlled fixture data exposes loading, retries, history errors, model errors, pending creation/saving/sending, legacy summaries, instructions, memory, dark appearance, larger text, host selection, and shared Sessions routes.

- Canvas: `native-durable-chat-ui-canvas/canvas.png`
- Searchable full-size viewer: `native-durable-chat-ui-canvas/index.html`
- State checklist and limits: `native-durable-chat-ui-canvas/coverage.md`
- Manifest: `native-durable-chat-ui-canvas/manifest.json`
- Live review: https://share.eugenechantk.me/durable-chat-canvas-20bf27/

Two explicit capture gaps remain: Mac Light appearance and the no-configured-host guard. Global Mac appearance and bundled host seeding were left alone. No product source changed for this review. API fixtures used private loopback ports 18975–18978, with no provider calls; production host 8766 was untouched. The isolated Mac copy exited after capture; its throwaway bundle was removed. The incomplete build cache from a failed relaunch was cleaned through FlowDeck.
