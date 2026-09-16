# Feature: Model Switch Transcript Notice

## User Story

As an LFG user, I want Codex's local model-switch confirmation to appear as a compact transcript notice so that command markup is not shown as a normal user message.

## User Flow

1. Open a Codex session in LFG.
2. Switch the model from the Codex command UI.
3. The transcript receives `<local-command-stdout>Set model to …</local-command-stdout>`.
4. LFG renders the confirmation using the same compact system-row treatment as transcript errors, without exposing the wrapper tags.

## Success Criteria

- [x] SC1: A message consisting of `<local-command-stdout>…</local-command-stdout>` is classified as `system / tool_result`, the same compact transcript row used by recoverable errors, and displays only its inner text. — **Verify by:** `bun test src/sessions-local-command-output.test.ts`.
- [x] SC2: When the wrapper is embedded in a human turn, the surrounding human text remains ordered user content and history/title readers ignore only the command output. — **Verify by:** `bun test src/sessions-local-command-output.test.ts`.
- [x] SC3: Ordinary user messages and malformed wrapper-like text retain their existing presentation. — **Verify by:** `bun test src/sessions-local-command-output.test.ts` plus adjacent Codex transcript suites.
- [x] SC4: The model-switch confirmation is visibly rendered with the same compact row layout used by transcript errors in the iPhone 17 Pro simulator. — **Verify by:** independent simulator screenshot audit.

## Test Strategy

Add focused Bun coverage at the canonical transcript-normalization seam, then run the adjacent Codex transcript suites and the full server suite. Use FlowDeck to run the existing iOS client against the normalized message and capture the final transcript row in Simulator.

## Tests

### Unit

- `src/sessions-local-command-output.test.ts`
  - Splits embedded output into ordered user / system-result / user rows — SC1, SC2.
  - Removes wrapper tags from standalone output — SC1.
  - Covers legacy user-message events — SC1.
  - Preserves ordinary and malformed text — SC3.
  - Keeps command output out of human history while retaining following prose — SC2.

### Regression

- `src/sessions-codex-user-messages.test.ts` — modern/legacy user-turn normalization.
- `src/sessions-codex-transcript.test.ts` — existing system/tool-result and error normalization.

## Implementation Details

Keep the change at the canonical server transcript-classification seam so every client receives the same message kind. Preserve the confirmation copy and the model persistence behavior; only its transcript rendering changes.

## Decision Log

- Treat local-command stdout as a neutral compact notice rather than semantically labeling it an error. Reuse the error row's visual component/layout so appearance stays consistent without corrupting the message kind.

## Verification Evidence

| SC | Command / action | Observed | Artifact |
| --- | --- | --- | --- |
| SC1–SC3 | `bun test src/sessions-local-command-output.test.ts` | 5 pass, 0 fail; the suite was red before implementation (4 failures) and green afterward | `src/sessions-local-command-output.test.ts` |
| SC2–SC3 | `bun test src/sessions-codex-user-messages.test.ts` | 8 pass, 0 fail | test output |
| SC1, SC3 | `bun test src/sessions-codex-transcript.test.ts` | 18 pass, 0 fail | test output |
| SC1–SC3 | `bunx tsc --noEmit -p .` | exit 0 | command output |
| SC1–SC3 | `bun test` | full repository suite exited 0 on two consecutive runs | command output |
| SC1–SC2 | `recentMessages` against the real rollout `01a0a0ae-b24c-7541-b2b7-0f24c76d7d07` | returned ordered `user/text`, `system/tool_result`, `user/text` rows with the wrapper removed | command output |
| SC4 | `flowdeck build` using the saved iPhone 17 Pro config | `** BUILD SUCCEEDED **` | FlowDeck build log |
| SC4 | independent FlowDeck screenshot/tree audit of `LFG_LOCAL_COMMAND_OUTPUT_FIXTURE=1` | PASS: exact inner text in a 370×42.33pt compact gray result row; wrapper tags absent; surrounding blue bubbles ordered; `localCommandOutputNotice` visible and enabled | `.codex/evidence/20260915-002250-model-notice-visual-audit/report.md` |

The dedicated `ios_visual_evidence_auditor` role could not start because its fixed model is unavailable on this account. A separate independent agent performed the same FlowDeck audit and produced the evidence above.

## Residual Risks

- The production UI path and exact real rollout were each verified, but together through separate seams: the real rollout was normalized directly and the normalized rows were rendered through the network-free UI fixture.
- The active host on port 8766 was not restarted because a restart drops in-memory session tracking. The new normalization takes effect after the next normal LFG host restart/deploy.

## Bugs

_None yet._
