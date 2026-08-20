# Feature: Conversation-aware autopilot titles

## User Story

As Eugene, I want autopilot titles to describe the session's overall work instead
of echoing the latest request, so related follow-ups keep a stable, useful title
and only a real change of subject causes a rename.

## User Flow

1. Autopilot selects an eligible session using the existing ownership, recency,
   checkpoint, and human-title protections.
2. It reads every genuine user message in chronological order, reusing the
   already-scanned history from its checkpoint and scanning only appended bytes.
3. The title model judges the full sequence for a sustained semantic topic shift.
4. Related follow-ups, refinements, bugs, verification requests, and implementation
   steps remain one topic; the model returns `null` when the current title still
   represents that work.
5. When the conversation has genuinely moved to a different workstream, the model
   proposes a concise title summarizing the session's established subject, not
   merely its newest request.

## Success Criteria

- [x] SC1: The retitler supplies every genuine user message, oldest-first, to the
  title decision. — **Verify by:** `allUserTurns` tests covering Claude and Codex
  transcripts, noise filtering, chronological order, and incremental reads.
- [x] SC2: Previously scanned user-message history is persisted in the checkpoint
  and only appended transcript bytes need rescanning. — **Verify by:** checkpoint
  parser compatibility tests and an incremental-history unit test.
- [x] SC3: The prompt explicitly treats related follow-ups as one topic and requires
  a sustained semantic shift before renaming. — **Verify by:** prompt regression
  tests for full-history labeling, latest-message resistance, and summarizing-title
  instructions.
- [x] SC4: Existing human-title, host-ownership, candidate selection, response
  validation, and title-cleaning behavior remains intact. — **Verify by:** all
  autopilot and session-turn tests.

## Platform & Stack

- **Platform:** Bun backend / CLI
- **Language:** TypeScript
- **Key frameworks:** Bun test, JSONL Claude/Codex transcript readers

## Steps to Verify

1. `bun test src/recent-user-turns.test.ts src/autopilot/retitle.test.ts`
2. `bun test src/autopilot/`
3. `bunx tsc --noEmit`
4. Run the independent verification auditor against the success criteria.

## Implementation Phases

### Phase 1: Full-history extraction and caching

- Scope: add incremental all-user-message extraction and checkpoint persistence.
- Success criteria covered: SC1, SC2.
- Verification gate: focused transcript and checkpoint tests pass.

### Phase 2: Conversation-level title policy

- Scope: pass full history to the retitle prompt and rewrite its drift/title rules.
- Success criteria covered: SC3, SC4.
- Verification gate: focused prompt tests and autopilot regression suite pass.

## Decision Log

- Persist truncated user-message history in the existing local retitle checkpoint.
  Re-reading multi-hundred-megabyte agent transcripts on every tick would regress
  the server's memory and event-loop safety; incremental scanning gives the model
  the complete user-message sequence without repeatedly processing tool output.
- Keep the existing batched LLM architecture and conservative `null` result. The
  behavior bug is in the evidence and decision rule, not scheduling or title
  provenance.

## Verification Evidence

| Criterion | Command / evidence | Result |
|---|---|---|
| SC1 | `bun test src/recent-user-turns.test.ts src/autopilot/retitle.test.ts` — full-history Claude and Codex extraction, 10-message ordering, filtering, and incomplete-row coverage | Pass: 50 tests, 0 failures. |
| SC2 | Same focused suite — appended-byte scan and legacy/new checkpoint parser coverage | Pass. Checkpoint history round-trips; malformed history forces a full rescan. |
| SC3 | `buildRetitlePrompt` regression test asserts full-history labeling, newest-message resistance, sustained-shift threshold, and workstream summarization | Pass. |
| SC4 | `bun test src/autopilot/` and `bun test` | Pass: 92 autopilot tests; 658 repository tests, 0 failures. |
| Types | `bunx tsc --noEmit` | Pass with no diagnostics. |
| Independent audit | `.claude/evidence/20260820-092743-verification-audit/evidence.md` | PASS across SC1-SC4; auditor reran focused tests, the autopilot suite, and TypeScript checking. |

## Bugs

_None yet._
