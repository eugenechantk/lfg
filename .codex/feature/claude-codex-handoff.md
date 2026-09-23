# Feature: Switch models and tools with conversation context

## Current user flow
- iOS: the existing **Switch model** menu contains exactly two sections. Current tool models appear first (**Switch in place**, or **Resume with model** for a closed session); the other tool appears second (**Switch to Codex** / **Switch to Claude Code**). Selecting a model switches in place when the tool matches, otherwise snapshots history and opens a separate session in the other tool with that exact model.
- Desktop: the session context menu has one **Switch to Codex** / **Switch to Claude Code** action. It starts the other tool using that CLI's configured default model. No desktop model picker or standalone Continue action.
- Cross-tool switches preserve the original session and working directory. The destination reads saved history, acknowledges context, and waits for the next instruction.

## Success criteria
- [x] SC1: Both transcript formats export full immutable raw history plus readable conversation. Verify Bun fixtures with modern Codex response items, tools and partial records.
- [x] SC2: iOS explicit target model is forwarded; desktop omits model and both CLI launchers honor the configured default. Verify Swift HTTP tests, desktop request tests, tmux argv tests and real bidirectional requests.
- [x] SC3: iOS displays current-tool models first and other-tool models second; no standalone Continue action. Same-tool live changes retain identity; cross-tool choices open the returned identity. Verify section/routing tests and recorded independent simulator audit.
- [x] SC4: New sessions recover saved context in both directions and original transcripts remain intact. Verify real Claude/Codex responses and hashes.
- [ ] SC5: Desktop exposes only the applicable Switch to tool action and preserves existing opener routing. Verify desktop build, headless feature suite and transport probes; GUI remains subject to macOS permissions.
- [x] SC6: Invalid source/target/model and failed bootstrap produce errors without orphan sessions or falsely reported success. Verify API probes and client validation tests.

## Decisions
- User correction replaces the earlier standalone Switch to Codex UI and expands direction to both tools.
- iOS explicitly chooses a model. Desktop deliberately inherits the destination CLI's configuration; Claude's usual LFG fallback remains unchanged outside this handoff path.
- Same-tool closed sessions resume with the selected model. Claude uses its native model command. Codex opens its native model/effort picker and applies a session-only selection; it rejects busy sessions, pending messages and unsent terminal drafts without overwriting them. Closed Codex sessions first resume their identity, then apply the chosen model.
- Cross-tool creation uses `/api/sessions/handoff` with `sessionId`, `agent`, optional `model`, and optional `user`; older hosts fail explicitly.
- Keep raw JSONL plus readable context under host LFG data. Do not synthesize private native rollout formats. Normalized prose is chronological; raw records retain branches, compaction metadata, tools and attachments.
- Only saved content is included. A still-running source may have unsaved output. The source remains independent.
- No host restart, commit, push, installation or TestFlight deployment is implied.

## Verification evidence
- Bun: 21 tests, 61 assertions passed across handoff export, native Codex picker, tmux argv and model normalization (`bun-tests-revised.txt`). TypeScript typecheck and whitespace checks pass.
- Swift: 581 XCTest cases (one existing skip), 175 Swift Testing cases passed; focused final section/HTTP tests also pass. Final iOS build succeeded (`ios-build-revised.jsonl`).
- Desktop: optimized Swift build and 136 headless checks passed; actual desktop request path launched both tools with no model override (`desktop-forward-revised.json`, `desktop-reverse.json`).
- Independent backend audit: both defaults, context recovery, byte-identical snapshots, source preservation, invalid requests and both failed-bootstrap cleanups pass. Native Codex model changes preserve PID/session/user-turn count/global configuration; unavailable model fails safely. See `../evidence/claude-codex-handoff/revised-audit/report.md`.
- Additional runtime guard: non-string model returns 400; unsent native draft returns 409 and preserves its exact text (`model-draft-preserved.txt`).
- iOS recorded cross-tool flows recovered the verification phrase in both directions. Audit found the model checkmark lagged until the next turn: fixed by preferring the actual native Codex status footer over the previous rollout turn model. Independent re-verification passed: confirmed changes update the coalesced session-list cache before HTTP success, and the first GET plus reopened iOS menu show the selected model. Closed Codex resume retains its identity and applies the chosen model; live changes retain both identity and pane.
- Evidence root: `.codex/evidence/claude-codex-handoff/`. No production host restart, installation or deployment; normal port 8766 remains PID 90347.

- Final independent iOS audit **PASS**: `../evidence/claude-codex-handoff/revised-ios-audit/evidence.md`, with four recorded flows and final section/checkmark screenshots. Both cross-tool directions, explicit models, source preservation, closed Codex resume, and live Codex switching verified.

## Prior iteration evidence
The earlier one-way standalone action passed backend and iOS checks; artifacts remain under `.codex/evidence/claude-codex-handoff/`. They do not verify the revised UI or reverse direction.

## Known verification blocker
Desktop GUI automation previously reported missing Accessibility and Screen Recording permissions. The macOS testing skill says: "Do not attempt to work around missing permissions; report and stop." Recheck read-only permission status; do not bypass. Headless desktop verification and real transport probes remain available.

## Verification blocker report
Desktop GUI testing remains blocked by denied Accessibility and Screen Recording permissions, reconfirmed with `axdriver doctor`. The macOS testing skill explicitly prohibits working around missing permissions. Native compilation, headless menu/request/opener checks, and real bidirectional transport passed; a recorded desktop right-click and terminal-opening flow is still unverified. No permission change was attempted.

## Changed files
- Desktop context action, handoff request and headless probe: `desktop/LFGSessions.swift`; usage notes in `desktop/README.md`.
- iOS menu and routing: `ios/LFG/SessionDetailView.swift`, `ios/LFG/SessionStore.swift`, `ios/LFGCore/Sources/LFGCore/SessionHandoff.swift`, `LFGClient.swift`; usage notes in `ios/README.md`.
- Backend transfer and model state: `src/handoff.ts`, `src/commands/serve.ts`, `src/tmux.ts`, `src/codex-model-switch.ts`, `src/codex-model-state.ts`, plus localized normalization export/model-state changes in `src/sessions.ts`. Concurrent transcript-compaction edits in the latter are preserved.
- Focused tests: `src/handoff.test.ts`, `src/codex-model-switch.test.ts`, `ios/LFGCore/Tests/LFGCoreTests/LFGClientHandoffTests.swift`, `SessionHandoffTests.swift`.
- No commits or deployment performed. Evidence is saved separately from product source.

## Cleanup
All four revised test destinations were closed through the isolated API with HTTP 200; evidence and transcripts retained. Test servers stopped; the production host was not restarted. See `cleanup-revised.json`.
