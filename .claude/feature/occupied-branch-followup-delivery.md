# Feature: Follow-up delivery with an occupied Claude branch composer

## User Story

As an LFG user, I want a follow-up sent to a Claude branch session to submit reliably even when that branch composer already contains a draft, so that LFG does not report a false failure or strand the follow-up.

## User Flow

1. A Claude branch session is idle with text already present in its composer.
2. The user sends a follow-up through LFG.
3. LFG identifies the actual branch composer, clears the stale/foreign draft, inserts the follow-up, and submits it.
4. The queue reports `delivered` or `queued`; it reports `failed` only if the follow-up genuinely remains in the composer after retries.

## Success Criteria

- [x] SC1: The live Claude `(Branch 3) ─` pane shape resolves to the `❯` composer text, not an earlier transcript or artifact line. — **Verify by:** a regression fixture in `src/tmux-composer-border.test.ts` using the captured affected pane tail.
- [x] SC2: Existing plain, named, wrapped, and Codex composer shapes retain their current parsing behavior. — **Verify by:** the focused tmux parser tests and full `bun test` suite.
- [x] SC3: A follow-up through the production `/send` path to the affected session no longer ends in `message never left the input box after retries`. — **Verify by:** reload the host, retry once, then inspect the queue record and normalized transcript.
- [x] SC4: The original failed row is reconciled without duplicate execution. — **Verify by:** compare transcript occurrences before and after the single retry and inspect the queue.

## Platform & Stack

- **Platform:** Bun/TypeScript server controlling Claude Code through tmux
- **Language:** TypeScript
- **Key frameworks:** Bun test, tmux

## Steps to Verify

1. Run the focused parser and send-queue tests.
2. Run the full Bun suite.
3. Reload the LFG host.
4. Retry the affected queue item exactly once.
5. Confirm one matching user turn and a non-failed terminal queue state.
6. Run an independent verification audit.

## Implementation Phases

### Phase 1: Reproduce and fix the parser

- Scope: Add the captured branch-number border shape and teach the border parser to recognize it without relaxing generic prose rejection.
- Success criteria covered: SC1, SC2
- Verification gate: Focused tests and full Bun suite pass.

### Phase 2: Production reconciliation

- Scope: Reload LFG, retry the affected item once, and confirm exactly-once delivery.
- Success criteria covered: SC3, SC4
- Verification gate: Queue and transcript evidence are green, followed by independent audit.

## Decision Log

- Treat this as a parser defect, not a generic Enter retry problem: the live `inputBoxFromPane` result is an earlier artifact path rather than the visible `❯` draft.
- Add a dedicated Claude branch-label predicate instead of lowering the global two-dash/short-label requirements, which protect against transcript prose being mistaken for a border.
- Retry the existing queue row after deployment rather than enqueueing a second copy.

## Verification Evidence

- SC1: The captured live pane returned an earlier artifact path before the change. `bun test src/tmux-composer-border.test.ts` failed on the new `NUMBERED_BRANCH_WITH_PROMPT` fixture, then passed after the targeted branch-marker predicate. A fresh live capture parsed as `❯ fix the guarantee card copy for the belly branch`.
- SC2: Focused parser/send tests: 38 passed, 0 failed. Full `bun test`: 735 passed, 0 failed across 63 files (1,544 assertions).
- SC3: Reloaded the supervised production host from PID `74137` to PID `7105`; `/api/ping` returned `ok: true`. Recovery queue item `6a9dca0e96360693` reached `delivered` in one attempt.
- SC4: Before recovery, the normalized transcript contained zero matching user turns. After the single recovery enqueue (`clientId=recovery-3459f46715252385`), it contained exactly one, id `a0cf0e87-e32b-4edd-afde-a260b6ddfe67`.
- Operational preservation: after the recovered turn completed, the live composer again contained the pre-existing draft `fix the guarantee card copy for the belly branch`; it remains unsent.
- Independent verification audit: **PASS** on SC1–SC4. Evidence: `.claude/evidence/20260904-192214-verification-audit/evidence.md`.

## Bugs

- `inputBoxFromPane` rejects Claude's numbered branch border when it is prefixed by the truncated branch prompt and ends in a single dash. It then pairs the bottom border with an unrelated older rule, so delivery confirmation reads transcript content as the composer and falsely reports that the follow-up never left.
