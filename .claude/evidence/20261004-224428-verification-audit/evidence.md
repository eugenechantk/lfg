# Verification Audit

Superseded: the Re-audit (2026-10-04 23:01 HKT) at the end of this file is PASS. Original verdict: FAIL (narrow). Every declared verification method passes, and the real seam passes. One race breaks SC3: two consumers checking the same mark in the same event-loop turn count the checked bytes twice. The fix is one line.

Timestamp: 2026-10-04 22:44–22:56 HKT (14:44–14:56Z)

Repository: /Users/eugenechan/dev/personal/lfg (host Eugenes-MacBook-Pro, branch main, dirty tree; only the 4 audited files were judged)

Surface: api / backend (Bun server modules; HTTP endpoint judged by code review only, per constraint)

Evidence directory: /Users/eugenechan/dev/personal/lfg/.claude/evidence/20261004-224428-verification-audit/

## Change Audited

- NEW `src/interrupt-marks.ts`: an in-memory mark per session, recording the time a stop was confirmed and the transcript size at that moment. `interruptStands` reads the bytes added since that size and drops the mark when a decisive line or a newer hook write appears.
- NEW `src/interrupt-marks.test.ts`: 9 tests.
- `src/session-state.ts`: the old body moved into `arbitrate()`, unchanged apart from `args.transcriptPath` becoming the `transcriptPath` parameter. When the verdict is `running` and a mark stands, the result becomes `{state:"idle", source:"interrupt"}`.
- `src/commands/serve.ts`: the POST `/api/sessions/:id/interrupt` handler calls `noteConfirmedInterrupt(m[1], sess.transcriptPath)` only when `r.stopped === true`.

## Success Criteria

| Criterion | Declared Method | Result | Evidence |
|---|---|---|---|
| SC1: a confirmed stop turns `running` into `idle` when neither layer has spoken since | `bun test src/interrupt-marks.test.ts` ("rewind case") | PASS | `02-sc1-4-interrupt-marks-tests.log` (9/9 pass). Real seam, endpoint-faithful: the pane was busy before the stop, `stopped:true`, then NEW read `idle/interrupt` on every tick for 8s while OLD read `running/transcript` (`12-…faithful-repro.log`). The pane shows the prompt rewound into the composer (`13-…pane-after-stop.txt`). The caller's repro also reproduced (`11-…caller-repro.log`). |
| SC2: a new turn after the stop reads `running`, announced by transcript or hook | tests "new prompt after stop", "hook after stop" | PASS (with the D1 caveat) | `02-…tests.log`. Real seam: the hook path read `running/hook` 400ms after resubmit, then `running/transcript`, and stayed running for 4s (`12-…`). The transcript path read `running/transcript` (`11-…`). Fixtures I/I'/K/H1' pass (`08-…`). |
| SC3: non-decisive writes after the stop (`ai-title`, `last-prompt`, `mode`) do not re-open the turn | test "metadata after stop" | **FAIL under a race**; PASS sequentially | The declared test passes (`02-…`). Sequential consults hold (`09-…`: 20/20 idle). Two `sessionTurnState` calls for the same session starting in the same tick or microtask, after `ai-title`+`last-prompt` land, leave the next quiet tick reading `running` (20/20). A 1ms offset never triggered it. See D1. |
| SC4: an unconfirmed stop (`stopped: false`/`null`) records nothing | code review of endpoint + test "no mark, no change" | PASS | `15-sc4-endpoint-diff.txt`: guard is `r.stopped === true` (strict). `interruptAndConfirm` returns `false` for not-sent and timeout, and `null` for a lost pane, so neither reaches the call. Test "no mark, no change" passes (`02-…`). |
| SC5: on the real `lfg-e4d53c` transcript, old code says `running`, and with a mark it says `idle` | `bun -e` probe on the live file | PASS | `04-sc5-real-transcript-probe.log`: the file was untouched since 14:21:25Z, before the 14:21:31Z stop. It has no assistant row after the last user row and no interrupt marker. Hook state is null. At 14:21:35Z: OLD (HEAD) gives `running/transcript`, NEW without a mark gives `running/transcript`, and NEW with a mark gives `idle/interrupt` on two ticks. Context: at real now, OLD gives `idle stalled:true` (STALL_MS), which matches the live server's `busy:false` (`05-…`). |
| SC6: existing suites stay green | `bun test src/session-state.test.ts src/turn-state.test.ts src/closing.test.ts` | PASS | `01-test-run.log`: caller's wider set, 235 pass, 0 fail, 15 files. `14-…literal.log`: the declared command ran 55 pass across only 2 files, because `src/closing.test.ts` does not exist and Bun skipped it silently. `03-tsc.log`: `tsc --noEmit` exit 0, no errors. |

Extra check asked by the caller ("old behavior changed when no mark exists?"): **no change**. `06-no-mark-differential-old-vs-new.log` compares HEAD `session-state.ts` with the new one on the 800 most recent real transcripts (Claude and codex). Each transcript ran 3 ways: real now, fresh, and no sessionId. That makes 2,400 comparisons with **0 mismatches**.

## Defects and risks found by adversarial testing

**D1 (confirmed defect, rare, breaks SC3).** In `noDecisiveSince` (`src/interrupt-marks.ts`), `m.checkedSize += Buffer.byteLength(...)` runs after an `await …text()`. Two concurrent consults both read the same tail, and both add its length. That pushes `checkedSize` past the real end of the file.
- Consequence A, the likely one (`08` A1, `09`): on the next quiet tick, `size < checkedSize` drops the mark, and the session reads "Working" again until STALL_MS. This is the pre-fix behavior, so the fix is silently undone.
- Consequence B (`08` A2): a new prompt that lands inside the skipped bytes is hidden. The session reads `idle` while a turn runs, until a decisive line lands past the over-counted offset. That is usually the first assistant row, seconds later.
- Reachability: three consumers share the one module-level map: the journal pump, the push watcher, and REST `listSessions`. The race needs two of them to start within 1ms for the same session, on a tick where non-decisive bytes were just appended. In both real cases nothing was appended after the stop (0 B over 8s in `12`, and the b08adb88 file is unchanged), so the chance is low.
- Suggested fix (not applied): capture `const from = m.checkedSize` before the await, then set `m.checkedSize = Math.max(m.checkedSize, from + bytes)`.

**Risks found, not criterion failures:**

- **R1, snapshot races (`08` B, B2).** A new prompt can be fully written, or half-written across the snapshot, in the moment between the last idle pane capture and `Bun.file().size` in the endpoint. That prompt is then treated as already checked. It reads `idle` until the next decisive line, then heals (B'). The window is milliseconds.
- **R2, codex (`08` G).** The mark also applies to codex rollouts, and codex mid-turn records (`agent_message`, `token_count`, `exec_command_end`, `response_item`) are non-decisive. If a codex stop is confirmed but did not actually take, the mark hides the running turn until it ends. For Claude, the next assistant row would heal it in seconds. A false confirmation needs `isBusy` to misread a codex pane, and `sessions.ts` notes that codex panes can briefly scrape idle mid-turn. Codex writes `turn_aborted` on a real stop, so the mark adds nothing for codex. Consider limiting marks to Claude transcripts.
- **R3, shrink then regrow (`08` E vs `10` E0).** Pure truncation fails safe and reads `running`. But if the file shrinks and then grows past the old size between two ticks, the tail starts mid-line and a decisive line can be missed. This needs a non-append rewrite, such as a sync replacement. It is the same append-only assumption `turn-state.ts`'s cache already makes.

**Checked, and these hold:**

- **Path identity.** For all 23 live pane-backed sessions, the endpoint's `transcriptPath` (from GET `/api/sessions`) is identical to what the pump and push watcher get from `resolveTranscript(sid)`: 23/23 the same, including 3 codex (`07-…`). A mismatch fails safe: the mark is dropped and the session reads `running` (`08` C, J).
- **Hooks.** Only `UserPromptSubmit`, `Stop`, `StopFailure` and `SessionEnd` write `stateAt`, in ms (`scripts/lfg-agent-hook.py`). A newer `stateAt` supersedes the mark (H1'). A newer lease `heartbeatAt` alone does not (H2).
- **Other edge cases.** More than 1 MiB of non-decisive bytes drops the mark (F), which fails safe. A mark left over from a stop that already wrote an interrupt marker still yields to the next prompt (I'). A second stop re-snapshots correctly (K).

## Artifacts

All in `/Users/eugenechan/dev/personal/lfg/.claude/evidence/20261004-224428-verification-audit/`:

- `01-test-run.log`: caller's suite set, 235 pass, 0 fail.
- `02-sc1-4-interrupt-marks-tests.log`: the 9 test names, 9 pass.
- `03-tsc.log`: tsc exit 0.
- `04-sc5-real-transcript-probe.log`: SC5. Record types and verdicts only, no content.
- `05-live-server-readonly.log`: live server (old code, started Oct 1) reports `busy:false` for b08adb88 through stall demotion. Filtered fields only.
- `06-no-mark-differential-old-vs-new.log`: 2,400 comparisons, 0 mismatches.
- `07-path-identity-endpoint-vs-pump.log`: 23/23 the same.
- `08-adversarial-fixtures.log`: cases A1–K.
- `09-race-through-sessionTurnState.log`: the D1 window measurement.
- `10-truncation-shrink-only.log`: E0 fails safe.
- `11-real-seam-caller-repro.log`: the caller's script, reproduced.
- `12-real-seam-auditor-faithful-repro.log`: the mark recorded at the endpoint's position, with OLD vs NEW per tick.
- `13-real-seam-pane-after-stop.txt`: pane capture showing the rewound prompt.
- `14-sc6-declared-command-literal.log`: SC6 command as written, where `closing.test.ts` is missing.
- `15-sc4-endpoint-diff.txt`: the endpoint diff.
- `probes/`: all audit scripts (`audit-*.ts`) plus `audit-old-session-state.ts`, the HEAD baseline with absolute imports.

## Commands

```sh
cd /Users/eugenechan/dev/personal/lfg
SP=/private/tmp/claude-501/-Users-eugenechan-dev-personal-lfg/a8acb137-be4a-449a-9059-fb5c41f20263/scratchpad
bun test src/interrupt-marks.test.ts src/session-state.test.ts src/turn-state.test.ts src/closing-actions.test.ts src/journal-pump.test.ts src/push
bun test src/interrupt-marks.test.ts
bun test src/session-state.test.ts src/turn-state.test.ts src/closing.test.ts   # SC6 literal
bunx tsc --noEmit -p .
git show HEAD:src/session-state.ts | sed 's#"\./\(hook\|turn\)-state\.ts"#"/Users/…/src/\1-state.ts"#' > $SP/audit-old-session-state.ts
bun $SP/audit-sc5.ts                       # SC5, now pinned to 14:21:35Z
bun $SP/audit-differential.ts 800          # no-mark differential
bun $SP/audit-path-identity.ts             # GET 127.0.0.1:8766/api/sessions (read-only) vs resolveTranscript
bun $SP/audit-adversarial.ts && bun $SP/audit-race.ts && bun $SP/audit-shrink.ts
bun $SP/stop-repro.ts $SP/stop-repro       # caller's real-seam repro
bun $SP/audit-stop-repro.ts $SP/stop-repro <evidence>/13-real-seam-pane-after-stop.txt
# cleanup: removed both scratch transcripts + leases + empty memory/ under
# ~/.claude/projects/-private-tmp-claude-501--…-scratchpad-stop-repro/ (dir removed); `tmux ls` shows no stoprepro-*
```

## Notes

- **Limitation.** The HTTP endpoint was not exercised live: no restart and no second `lfg serve`, per the constraints. The wiring was judged by code review. The marked path is the same string the consumers use (23/23 live rows), and the real seam drove the same `interruptAndConfirm`, `noteConfirmedInterrupt` and `sessionTurnState` functions the endpoint calls. The feature doc's step 3 (live server, `busy` in `GET /api/sessions` drops within about 2s) is still **unverified until a restart**.
- **Doc fix needed.** SC6's declared command names `src/closing.test.ts`, which does not exist. Bun skips it silently. The intended file is `src/closing-actions.test.ts`.
- **Test count.** The caller reported 9 + 208 tests. I counted 235 in the same set, probably because other sessions changed test files in the dirty tree. All pass.
- **Implementer's repro log.** Its "composer holds prompt again?" line printed `false` both times, because the regex misses, not because the rewind failed. The pane capture (`13`) shows the prompt back in the composer.
- **Side effects of the real seam.** The two scratch Claude sessions ran about 15s each in `stoprepro-*` panes and the live lfg server could see them. Any journal or push activity they caused is outside my control. Both panes were killed and their transcripts removed.
- **Secret handling.** The b08adb88 transcript's content was never printed or copied. Probes emitted only record types, sizes and verdicts.

---

# Re-audit

Verdict: **PASS.** D1 is fixed, and SC3 now holds under concurrent readers. R2 is closed at the endpoint. SC1–SC6 all hold. This replaces the FAIL verdict above.

Timestamp: 2026-10-04 22:58–23:01 HKT · same host, same constraints. Artifacts are numbered 16–25 in the same evidence directory.

## Changes re-verified

1. **D1.** `noDecisiveSince` now saves `const from = m.checkedSize` before the await and sets `m.checkedSize = Math.max(m.checkedSize, from + bytes)`.
2. **New test.** "concurrent readers in one tick do not double-count checked bytes".
3. **R2.** The endpoint now marks only when `r.stopped === true && sess.agent === "claude"`. That call is still the only one that writes a mark: `grep noteConfirmedInterrupt(` finds `serve.ts:3043` and nothing else (`24-reaudit-endpoint-diff.txt`).

## Results

| Check | Result | Evidence |
|---|---|---|
| A1 race probe, 20 trials per start offset, through `sessionTurnState` | PASS. Every offset reads `idle` 20/20, including same tick and next microtask, which were 20/20 `running` before the fix. | `19-reaudit-race-through-sessionTurnState.log` |
| Adversarial fixtures | A1 and A2 now OK. A3, C, F, G', H1, H1', H2, I, I', J and K still OK. B, B2 and E remain (R1/R3, accepted). G remains at module level, but the R2 endpoint gate makes it unreachable (no codex mark is ever written). | `20-reaudit-adversarial-fixtures.log` |
| Readers that see different file sizes (new probe) | PASS. M1 and M3 read `idle` on quiet ticks and `running` after a new prompt, 20/20 each. In M2 the reader that sees the new prompt drops the mark, and the next ticks read `running`, 20/20. | `22-reaudit-race-mixed-ranges.log` |
| The new test catches the old bug (mutation check) | PASS. I ran the new test file against a scratch copy with the old `+=` line restored. Only "concurrent readers…" fails (9 pass, 1 fail). On the real code all 10 pass. | `21-reaudit-mutation-check.log`, `17-reaudit-interrupt-marks-tests.log` |
| SC3 | PASS (declared test, A1 probe, mixed-size probe) | `17`, `19`, `22` |
| SC1, SC2, SC4, SC5 | PASS. They are unaffected: the fix changes only the path that reads appended bytes. SC4 keeps its strict `=== true` and gains the Claude-only check. | `17`, `24` |
| SC6 suites | PASS. 236 pass, 0 fail across 15 files (+1 = the new test). | `16-reaudit-test-run.log` |
| tsc | PASS, exit 0 | `18-reaudit-tsc.log` |
| No mark, no change | PASS. 2,400 comparisons, 0 mismatches. | `23-reaudit-no-mark-differential.log` |

One harmless side effect, for the record (M2): when two readers race and only the second sees a new prompt, the first may still report `idle` for that one tick. The next tick reads `running` everywhere, because the mark is gone.

## R1 and R3: are they worse than stated?

**R3: no.** Claude transcripts are append-only. The sync tool's hourly mtime rewrites do not change size. `turn-state.ts`'s size-keyed cache already relies on the same assumption. Pure shrinking fails safe (`10`).

**R1: the window is about as stated, but the effect can last longer than "seconds".**

- **Window.** It runs from the tmux snapshot inside the confirming capture to the synchronous `Bun.file().size` call. The capture plus `isBusy` takes p50 6.7ms, p95 9.7ms and max 12.1ms in an idle Bun process (`25-reaudit-r1-capture-latency.log`). Between the capture and the note, only `void logOp(...)` runs, and its synchronous part is trivial. In the live server, event-loop delay adds to this window. The project's CLAUDE.md documents periodic stalls of about 170ms, which I did not measure here. So the window is a few ms typically, and up to a few hundred ms in a stall.
- **Most plausible trigger.** A message already waiting in Claude's own input queue, which Claude runs right after the rewind. Its user row and its `UserPromptSubmit` hook (`at` earlier than `m.at`) can both land inside the window. Then both layers count as "spoken before the stop".
- **Effect.** The new turn reads `idle` until its first assistant row. On Opus at xhigh effort, thinking before the first row can take tens of seconds, not just a few. A capture that sees the queued turn running instead gives `stopped:false`, so no mark is written. That is the safe and usual outcome.
- **My call.** It is still a low-likelihood documented risk, and it does not block. A cheap way to close it fully: capture the transcript size and the time *before* each confirming capture (or before sending Escape), and pass them into `noteConfirmedInterrupt` instead of reading them after. A decisive line written during the confirm window would then supersede the mark. In the interrupted-with-output case Claude writes the `[Request interrupted` marker, so the transcript still reads `idle` there.

## Re-audit commands

```sh
cd /Users/eugenechan/dev/personal/lfg
SP=/private/tmp/claude-501/-Users-eugenechan-dev-personal-lfg/a8acb137-be4a-449a-9059-fb5c41f20263/scratchpad
bun test src/interrupt-marks.test.ts src/session-state.test.ts src/turn-state.test.ts src/closing-actions.test.ts src/journal-pump.test.ts src/push
bun test src/interrupt-marks.test.ts
bunx tsc --noEmit -p .
bun $SP/audit-race.ts            # A1, 20 trials x 6 offsets
bun $SP/audit-adversarial.ts
bun $SP/audit-race-mixed.ts      # readers that see different sizes
bun $SP/audit-differential.ts 800
bun $SP/audit-capture-latency.ts # R1 window (throwaway `sleep 60` tmux pane, killed after)
# mutation check: scratch copies of interrupt-marks.ts (old `+=` line), session-state.ts and the
# test file with imports rewritten, run in $SP/mutant/ (see 21-reaudit-mutation-check.log)
```

I did not run the real seam again. The fix changes only the path that reads bytes appended after the stop, and both real stops appended 0 bytes. The endpoint gate is not on the path the repro drives. The live endpoint is still unverified until a server restart (feature doc step 3).
