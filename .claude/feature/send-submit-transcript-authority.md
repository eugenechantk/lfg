# Send submit policy: type, Enter, let the transcript judge (2026-09-17)

## Decision

`deliver()` in `src/sendq.ts` no longer confirms the draft in the composer before pressing Enter, and no
reading of the composer can fail a send. Eugene's call, after the fourth border-parser fix in five weeks:
"Why not just always press enter anyways, and then verify in the transcript."

## Evidence (`~/.lfg/sendq.log`, 2026-08-06 → 2026-09-17)

| outcome | attempt 1 | attempts 2–3 |
|---|---|---|
| queued / delivered | 1202 | 1 |
| failed "never left the input box after retries" | 0 | 54 |
| failed "not in a tmux pane" | 15 | 0 |

The pre-Enter check existed to catch lost keystrokes. They essentially never happen (one rescue in six
weeks). The check itself, via the composer-region parser, was the only source of delivery failures: every
one of the 54 was the parser misreading the pane, concluding the draft was absent, wiping it with Ctrl-U,
retyping, and giving up. Prior fixes: wrapped bottom border, `(Branch) ──`, `(Branch 3) ─`, wrapped
`(Branch\n2) ─` + dead `›` fallback (`.claude/diagnosis-send-fails-wrapped-branch-label-20260917.md`).

## New flow

1. Dismiss a selector / rating overlay if one is open (unchanged; Enter into those is harmful, and those
   detectors do not use the composer-region parser).
2. Ctrl-U, type (or bracketed-paste for multi-line).
3. Settle: up to 10 × 150ms, stopping early the moment the composer visibly holds the draft. An
   unreadable composer just waits the full beat. This exists so the Enter is not read as a pasted newline.
4. Enter, then watch up to 3.6s. `submitOutcome(transcriptGrew, held, isCommand)`:
   transcript grew → delivered; composer readable-and-empty or unreadable → queued (slash command →
   delivered); composer positively still holds the draft → keep watching, then Enter again (≤ 3 rounds).
5. If it never surfaces and the composer never reads as cleared, park it **queued**, not failed.
   `reconcileQueued` promotes it when the text surfaces and only re-drives (then fails) once a provably
   idle agent has not picked it up. "message never left the input box after retries" no longer exists.

The composer parser (`inputBoxFromPane`) is still used, as an accelerator and as a positive-only hint. Its
failure mode is now "wait a bit longer", never "lose the message".

## Verification

- Unit: `src/sendq-insert.test.ts` pins `submitOutcome` (no observation yields a failure); full suite
  852 pass; `tsc` clean.
- Live, deployed server (pid 76285, 14:38:49): throwaway session `bee568e0…` spawned under this one.
  Probe 1 idle → delivered 0.9s. Probe 2 (25s Bash turn) → queued then reconcile-delivered. Probe 3 sent
  with `busy: true` → queued 0.5s, surfaced-delivered 0.7s. All attempts = 1. Session closed.
- Not exercised live: a pane whose composer is unreadable. The code path no longer branches on that
  reading, so the unit test is the discriminating check.
