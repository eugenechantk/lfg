# Feature: Codex multiline follow-up delivery

## User Story

As an LFG user, I want a multiline follow-up sent to an idle Codex session so that I can continue the conversation without retrying or opening tmux.

## User Flow

1. Open an existing idle Codex session.
2. Enter a follow-up containing multiple paragraphs.
3. Send it.
4. LFG submits the follow-up exactly once and the session starts the next turn.

## Success Criteria

- [x] SC1: A multiline Codex composer is recognized as holding the inserted draft instead of being re-pasted on every delivery attempt. — **Verify by:** regression test using the captured multiline composer shape from `codexy-153628-89613`.
- [x] SC2: Existing Codex and Claude composer parsing remains correct. — **Verify by:** focused tmux/send-queue tests.
- [x] SC3: The reported follow-up is delivered to `codexy-153628-89613` once, without another failed queue row. — **Verify by:** live queue API, transcript API, and pane capture.
- [x] SC4: The server-side test suite remains green. — **Verify by:** `bun test`.

## Platform & Stack

- **Platform:** Bun/TypeScript backend controlling a Codex terminal UI through tmux
- **Language:** TypeScript
- **Key frameworks:** Bun test, tmux, local HTTP API

## Steps to Verify

1. Run the focused composer/send-queue regression tests.
2. Run `bun test`.
3. Reload the LFG server so the live endpoint uses the fix.
4. Remove the stranded draft from the reported session, retry one failed queue item, and observe a single new user transcript turn.
5. Confirm the queue item reaches `delivered` and no duplicate turn appears.

## Implementation Phases

### Phase 1: Reproduce and fix composer recognition

- Status: **Verified**
- Scope: Capture the multiline Codex shape, add regression coverage, and correct draft recognition/clearing with the smallest safe change.
- Success criteria covered: SC1, SC2
- Verification gate: Focused tests pass.

### Phase 2: Regression and live verification

- Status: **Verified**
- Scope: Run the suite, reload the local server, recover the reported follow-up, and confirm end-to-end delivery.
- Success criteria covered: SC3, SC4
- Verification gate: Full suite and live API/transcript evidence pass.

## Decision Log

- Treat `codexy-153628-89613` as the tmux name, resolved through the sessions API to `019fff33-6f44-7e00-8b36-b57f762833ce`.
- Preserve the user's message and session. Diagnose from the failed queue rows and pane before retrying one existing row after the fix.

## Verification Evidence

| Criterion | Command/action | Observed result | Artifact |
| --- | --- | --- | --- |
| SC1 | `bun test src/tmux-codex-pane.test.ts src/sendq-insert.test.ts` | 17 pass, 0 fail. The new captured multiline shape returns all paragraphs; before the implementation the new assertion failed because only the first line was returned. | Console output in task transcript; regression fixture in `src/tmux-codex-pane.test.ts`. |
| SC2 | Same focused test run | Existing busy/idle, typed draft, selector, Claude composer, and insertion-outcome tests all passed. | Console output in task transcript. |
| SC3 | Cleared the duplicated unsent composer in `codexy-153628-89613` after user approval, then posted exactly one preserved copy of the original follow-up through `/send`. | Queue row `b4f1e06a8b3978fb` reached `delivered` on attempt 1. The full transcript contained exactly one matching user turn. | Local queue and transcript API responses in task transcript. |
| SC4 | `bun test` | 610 pass, 0 fail across 53 files; 1193 assertions. | Console output in task transcript. |
| Independent audit | Verification auditor repeated focused tests, the full suite, and an equivalent disposable live send without touching the reported session. | **PASS**. One-attempt delivery, exactly one matching user turn, and exactly one `MULTILINE_ACK`; disposable session closed. | `.claude/evidence/20260814-183047-verification-audit/evidence.md`. |

Runtime reload: the supervised LFG server restarted as PID `16291`; `/api/ping` returned `{"ok":true}`.

## Bugs

_None open._

- Resolved: The Codex composer parser returned only the `›` prompt line. For a multiline draft whose normalized 48-character confirmation prefix extended onto the next visual line, the sender concluded insertion failed, pasted again, and eventually failed while leaving duplicated text in the composer.
