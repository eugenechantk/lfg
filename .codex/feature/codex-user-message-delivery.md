# Codex user message ordering and delivery

## User Story

User messages must appear before their replies, and accepted follow-ups must leave the queue without being sent again.

## User Flow

Send a prompt, read its response, then send a follow-up. The host normalizes user turns in transcript order and confirms delivery as soon as the turn appears.

## Success Criteria

- [x] SC1: Modern Codex user records appear before their replies in full, bounded, paged, and incremental normalization — verify with `src/sessions-codex-user-messages.test.ts` and replay of lfg-37d7c4.
- [x] SC2: A queued follow-up present in modern Codex records becomes delivered, without re-drive, while busy or idle — verify with parser-to-queue regression tests.
- [x] SC3: Injected context stays hidden, older event-based transcripts remain single-copy, and repeated real prompts remain distinct — verify with regression tests.
- [x] SC4: User prompt readers recognize modern turns — verify recent/all/last prompt readers against fixtures and the reported session.

## Platform & Stack

TypeScript/Bun host. No client code changes expected.

## Implementation

Recognize response-item user content tagged `user.text` by Codex's content metadata; keep the existing event-based path for older rollouts. Apply the same extraction to prompt-history readers.

## Decision Log

- Preserve existing message identities and timestamps, including legacy event IDs. Modern records receive the existing normalizer's deterministic ID.
- Use typed content metadata to avoid rendering injected instructions or duplicating older response-item/event pairs. Local old-format evidence has turn metadata but no content-item kinds; the reported session has content-item kinds and no user-message events.
- Preserve all pre-existing working-tree edits. Do not rewrite transcripts, manipulate the live queue database, or resend anything to the example session.

## Investigation

Session `lfg-37d7c4` resolves to `01a0763b-ad64-7f80-b7fb-cfa1dd3cbaf7`. Its rollout contains four real user records, all skipped by the existing parser. The follow-up appears three times at 10:25:40, 10:25:57, and 10:26:08 UTC on 2026-09-06. The live queue reports failed after two redeliveries. This explains both missing user turns and false queue status, including duplicate execution.

## Verification Evidence

- Regression reproduced before implementation: 7 failing tests, including missing user turns, stuck queue while busy, and resend while idle.
- `bun test src/sessions-*.test.ts src/sendq*.test.ts src/journal-pump*.test.ts src/recent-user-turns.test.ts`: 150 pass, 0 fail, 344 assertions. Evidence: `evidence/codex-user-message-delivery/tests.log`.
- `./node_modules/.bin/tsc --noEmit`: exit 0. Evidence: `evidence/codex-user-message-delivery/typecheck.log` (empty, no diagnostics).
- SC1/SC4: read-only replay of the original session through 10:26:13 UTC: all four real user turns recovered before their responses; full/bounded/incremental readers agree; recent/all/last prompt readers agree. Evidence: `evidence/codex-user-message-delivery/replay.json`.
- SC2: original follow-up replayed against queue reconciliation while busy and idle: delivered, changed=true, kick=false in both cases. Same replay evidence.
- SC3: tests cover legacy response/event pairs, repeated real prompts, hidden injected content, and mixed content provenance.
- Replay harness corrected to freeze the original reported exchange. The session received more messages during investigation and exceeded the default tail window; a full-reader comparison must explicitly use the same byte window.
- Independent audit PASS: `evidence/codex-user-message-delivery/audit/report.md`. Dedicated auditor model was unavailable; an independent default agent performed the audit. Its first broad run had three discovery timeouts, all passed on targeted retry; no assertion failures.
- Reloaded only the supervised LFG host process (56988 → 73672). Existing example Codex PID stayed 51188 and live session count stayed 7. Host API now reports latest user text instead of null: `api-before.json` / `api-after.json`.
- Live `GET /api/sessions/01a0763b-ad64-7f80-b7fb-cfa1dd3cbaf7/messages?full=1`: all original four user turns present before their replies, with correct timestamps; eight total user turns by final verification. Evidence: `api-history-after.json`.
- Live queue endpoint after reload returns an empty queue (terminal failures are not recovered into memory). Evidence: `api-queue-after.json`. No synthetic sends or direct database manipulation.

## Limitations

Previously failed queue rows and already-produced duplicate answers are historical state. This code fix does not rewrite them. The running host has loaded the updated code. Reopening the client session refreshes cached history. No client UI automation was run; verification covers the host API and transcript/delivery logic.
