# Independent verification: PASS

Scope: host normalization and prompt-history support for modern Codex user response records in `src/sessions.ts`, and its regression tests. No source files changed during audit.

| Criterion | Result | Evidence |
| --- | --- | --- |
| SC1 — real user turns precede replies across readers | PASS | Independent `replay.ts` reread the reported rollout through 2026-09-06T10:26:13Z. Four user turns recovered among 18 normalized messages. Full, bounded (same byte window), incremental, and 3-item paginated readers were asserted identical. `replay.json` records the timeline. |
| SC2 — accepted queue follow-ups acknowledge without resend | PASS | Independent real-rollout parser-to-queue replay returned delivered, changed=true, kick=false with both busy and idle states. Regression suite also passes both variants. |
| SC3 — injected context hidden, legacy pairs single-copy, repeated turns distinct | PASS | Eight new regression tests pass, including mixed content provenance, legacy response/event pairs, and repeated prompt identities. Real rollout inspection confirms provenance arrays distinguish injected records and real input; no legacy user_message events occur in the frozen reported exchange. |
| SC4 — user-history readers support modern turns | PASS | Independent replay asserted recent/all/last readers against user.text records extracted directly from raw JSON. |

## Commands and observed results

- `bun test src/sessions-*.test.ts src/sendq*.test.ts src/journal-pump*.test.ts src/recent-user-turns.test.ts`: 147 pass, 3 timeouts in unrelated live-discovery `sessions-resumable-closed.test.ts`; no assertion failures (`tests.log`).
- `bun test --timeout 30000 src/sessions-resumable-closed.test.ts`: all three previously timed-out tests pass (`resumable-retry.log`). All 150 broad-suite cases therefore passed across the run and targeted retry.
- `bun test src/sessions-codex-user-messages.test.ts src/sendq-reconcile.test.ts src/recent-user-turns.test.ts`: 23 pass, 0 fail across the two existing matched files (`scoped-tests.log`; the named sendq-reconcile path does not exist, queue coverage is in the new tests and broader suite).
- `bun .codex/feature/evidence/codex-user-message-delivery/audit/replay.ts`: exit 0; all independent assertions pass (`replay.json`).

Implementation review found the change restricted to provenance-aware text extraction and its two required consumers. Existing normalization order, legacy event identity, timestamp derivation, and queue reconciliation are preserved.

## Limits

This is a code-and-local-rollout verification. The running host was intentionally not restarted or sent messages by the auditor; root will verify HTTP history after loading new code. Already failed queue rows and historical duplicate answers are not repaired by this patch. No database operations performed.
