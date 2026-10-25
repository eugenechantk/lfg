# Independent verification: PASS

The current implementation passes SC1–SC5 at the requested host and client-contract scope. No unresolved defect remains from this audit.

## Evidence

- `final-tests.txt`: 157 tests pass across parser, status, journal, state, parity, and push suites. No failures.
- `probe.ts` and `probe-results.json`: independent fixtures exercise the captured real pane, quoted prose, failed captures, incomplete renders, wrapped borders, and stalled turns.
- `process-reload.txt`: a fresh Bun process rereads persisted state. The countdown changes, but the stable ID remains unchanged and no incident is added.

## Success criteria

| Criterion | Result | Evidence |
| --- | --- | --- |
| SC1: Recognize live limits without ordinary prose | PASS | The captured real pane parses with its full retry text. A fenced quotation immediately above the composer does not parse. Parser tests cover wrapping and other limit names. |
| SC2: Preserve incidents without repeated countdown rows | PASS | One stable ID survives rereads, a fresh process, failed captures, unbordered captures, and adjacent wrapped border rows. A verified recovery permits a later incident. Provider JSONL remains unchanged. |
| SC3: Journal, history, and pagination | PASS | Tests verify publication after prior discovery, stable-ID replay, tail catch-up gating, recent/full history, and backward pages. Source inspection confirms the pump checks its offset and partial buffer before publication. |
| SC4: Pause, retry details, recovery, and queue semantics | PASS | Limits produce `blocked` with `usage_limit` and raw details. A complete composer without the meter clears the active observation. A stalled transcript remains busy during native retry. Both REST and pump pass the override. Push inspection also recognizes native retry and suppresses stale questions. |
| SC5: Existing client rendering contract | PASS | Swift decodes `apiError` and `statusReason`; assistant text uses TextBubble and adds the API error label. `isBlocked` gates PausedBannerView. `usage_limit` selects the generic Build paused title, and raw statusDetail supplies the retry/reset details. |

## Defects found and verified fixed

1. Partial captures cleared active incidents and created duplicate rows on the next poll. Unknown captures now preserve active state, including adjacent wrapped border rows.
2. A quoted meter near the composer became an API error. Parsing now rejects a meter followed by prose or a closing code fence.
3. The stall timeout treated a long native retry as idle. The nativeRetry override now preserves the in-flight turn. This also preserves the existing Send Now decision path.
4. Failed captures preserved storage but briefly cleared reported health. The observer now returns the persisted active notice.
5. The independent poll loop could publish a notice before earlier transcript rows. Publication now waits for the transcript tail and its partial buffer.

## Source contracts checked

- `src/claude-system-notices.ts`: parser, storage, deduplication, recovery, history merge.
- `src/journal-pump.ts`: stable publication, tail ordering, prompt and busy derivation.
- `src/sessions.ts`: current health, native retry override, recent/full history and pagination.
- `src/commands/serve.ts`: stale prompt suppression.
- `src/session-state.ts`, `src/sendq.ts`, `src/push/watcher.ts`: busy override, queue behavior, push parity.
- `ios/LFGCore/Sources/LFGCore/Models.swift`: decoding and blocked predicate.
- `ios/LFG/Components.swift`: assistant text, API error label, paused banner title and detail.
- `ios/LFG/SessionDetailView.swift`: paused banner gating.
- `ios/LFG/SessionStore.swift`: journal replay deduplication by stable ID.

## Limits

This audit verifies tests, fresh-process persistence, captured-pane fixtures, and source contracts. It does not claim a deployed-host check or actual visual rendering evidence. The auditor did not restart the host, touch production transcripts or databases, send session input, launch Apple apps, commit, or push. All auditor-written files remain in this audit directory.
