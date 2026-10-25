# Claude system notices

## User story

Claude can wait for a usage reset without writing an error to its transcript. LFG must show the reason and retry details.

## Success criteria

- [x] SC1: Recognize Claude's live weekly/session limit retry meter without matching ordinary assistant prose. Verify with parser regression tests and the captured live pane.
- [x] SC2: Preserve each observed incident across reloads and host restarts without editing provider transcripts or repeating countdown updates. Verify with temporary sidecar tests.
- [x] SC3: Deliver the notice through live journal events, recent/full history, and backward pagination. Verify with pump and transcript integration tests.
- [x] SC4: Classify the current limit as paused with its retry details; clear it after the meter disappears. Verify with session health and prompt tests.
- [x] SC5: Preserve the existing API error rendering contract. Verify the normalized message shape and existing client rendering path through independent audit.

## Scope and stack

TypeScript host only. Existing clients already render assistant text with `apiError: true` and the paused status banner. No client redesign or release is needed.

## Decision log

- Read only Claude's meter above the bordered composer. Never scan conversation text for operational state.
- Store LFG observations in a separate sidecar beside the transcript. Keep Claude's transcript intact.
- Keep the native retry in flight for send-queue purposes. The health status explains the pause without submitting or interrupting anything.
- Use an additive `usage_limit` reason for Claude limits. Existing clients render a generic paused banner with the retry details, without claiming the account lacks credits.
- No host restart, deployment, commit, or push is authorized by this fix request.

## Verification evidence

- SC1: `live-parser-proof.txt` matches the captured real weekly meter. Parser regressions reject quoted prose, old scrollback, and composer input.
- SC2: Temporary sidecar tests preserve one incident across countdown updates, failed captures, partial renders, and wrapped borders. The independent fresh-process probe confirms restart persistence. Provider JSONL remains unchanged.
- SC3: Tests cover live journal publication, replay IDs, delayed transcript tail publication, recent/full reads, and backward pagination. See `final-regressions.txt`.
- SC4: Tests confirm `blocked` with `usage_limit` and raw retry details, clearing on recovery, suppressing stale questions, and preserving a retry across the stall timeout. REST, journal, and push share the native retry override.
- SC5: Independent audit confirms the current Swift decoding and rendering path accepts the error message and paused status. See `audit/REPORT.md`. This is source-contract verification; no visual or deployed-host verification is claimed.
- Final regression command: `bun test --timeout 60000 src/sessions*.test.ts src/transcript.test.ts src/journal*.test.ts src/prompt-kind.test.ts src/tmux-*.test.ts src/session-state.test.ts src/session-state-parity.test.ts src/turn-state.test.ts src/claude-system-notices.test.ts src/push/watcher.test.ts src/commands/serve-fork.test.ts src/commands/serve-transcript-status.test.ts` — 459 pass, 0 fail across 42 files.
- `bunx tsc --noEmit -p .` exits 0. `git diff --check` exits 0.
- The initial broad run hit five default five-second timeouts in resumable tests that enumerate live processes. The same tests pass with a sixty-second bound; the complete final batch also passes.
- Independent audit: PASS, 157 tests plus separate fixtures and fresh-process persistence evidence.
- No deployment, host restart, commit, push, or Apple app launch.

## Bugs

- Fixed: the weekly retry meter was absent from provider JSONL and LFG history.
- Fixed audit findings: partial-render duplicates, quoted-meter false positives, stale health after failed captures, early live notice delivery, and long retries classified as idle.
- No open bugs within the verified scope.

## Recheck on October 23

- The requested fix was already present in this working tree. This recheck preserves that implementation and unrelated edits.
- The fresh regression run passes all 459 tests across 42 files. See `claude-system-notices/recheck-regressions.txt`.
- `bunx tsc --noEmit -p .` exits 0. See `claude-system-notices/recheck-types.txt`. `git diff --check` also exits 0.
- Read-only checks of the current Claude panes found no active weekly retry meter. The saved real pane remains the reproduction fixture.
- The host serving port 8766 started on October 22 at 22:33:54 HKT. The notice module changed on October 23 at 00:51:49 HKT. The running process has not loaded this fix.
- No host restart, deployment, session input, commit, or push was performed.
- Independent recheck: PASS for SC1–SC5. The auditor ran 67 targeted tests and a separate captured-pane and fresh-process probe. See `claude-system-notices/recheck-audit/REPORT.md`. Client rendering was checked through source contracts; no visual or deployed-host verification is claimed.
