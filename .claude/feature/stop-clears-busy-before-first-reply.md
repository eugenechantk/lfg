# Feature: Stop clears "Working" even before the first reply

## User Story

As Eugene, when I press Stop on a session in the app, I want the session to leave
"Working" within a couple of seconds, so I can trust that the stop worked and do not
press it again.

## Diagnosis (2026-10-04, session `lfg-e4d53c`, sid `b08adb88…`)

- Eugene pressed Stop at 14:21:31Z and again at 14:28:03Z. `data/ops.log` records both as
  `sent: true, stopped: true` in ~0.26s. The pane confirms Claude is idle: the prompt
  sits back in the composer.
- lfg still reported `busy: true`. `sessionTurnState` on the real transcript returns
  `{"state":"running","source":"transcript"}`.
- Cause: the stop landed 7s after submit, **before Claude wrote any assistant row**. In
  that case Claude Code rewinds — it puts the prompt back in the composer and writes
  **no** `[Request interrupted` marker. The newest decisive transcript line is the user
  prompt, so `classifyTurnLine` says `running`. No hook state exists for this session
  (the lease has no `state`), and hooks would not help anyway: `Stop` does not fire on
  Escape.
- Result: "Working" holds until `STALL_MS` (15 min) demotes it. Eugene retries Stop in
  the meantime. Every one of the 31 interrupts in `ops.log` since 2026-08-06 confirmed a
  stop, so the stop itself is reliable; the label is what lags.
- The transcript carries no rewind signal at all (checked every record: `last-prompt`,
  `prompt_snapshot` attachment, uuids). A transcript-only fix is impossible.

## User Flow

1. Eugene sends a prompt, then presses Stop before Claude replies.
2. The server sends Escape and confirms the pane went idle (existing behavior).
3. Within one pump tick (~1s) the session reads idle in the list, REST snapshot and
   Live Activity.
4. Eugene sends a new prompt. The session reads busy again at once.

## Success Criteria

- [x] SC1: A confirmed stop turns a `running` verdict into `idle` when neither layer has
  spoken since — **Verify by:** `bun test src/interrupt-marks.test.ts` ("rewind case").
- [x] SC2: A new turn after the stop reads `running` again, whether the transcript or the
  hook announces it — **Verify by:** tests "new prompt after stop", "hook after stop".
- [x] SC3: Non-decisive writes after the stop (`ai-title`, `last-prompt`, `mode`) do not
  re-open the turn — **Verify by:** test "metadata after stop".
- [x] SC4: An unconfirmed stop (`stopped: false` / `null`) records nothing — **Verify by:**
  code review of the endpoint + test "no mark, no change".
- [x] SC5: On the REAL `lfg-e4d53c` transcript, old code says `running`; with a mark the
  verdict is `idle` — **Verify by:** `bun -e` probe against the live file (discriminating
  case).
- [x] SC6: Existing suites stay green — **Verify by:** `bun test src/session-state.test.ts
  src/turn-state.test.ts src/closing-actions.test.ts src/journal-pump.test.ts src/push`.

## Platform & Stack

- **Platform:** Backend (lfg Bun server)
- **Language:** TypeScript
- **Key frameworks:** bun:test

## Steps to Verify

1. `bun test src/interrupt-marks.test.ts src/session-state.test.ts src/turn-state.test.ts`
2. `bun -e` probe on the real transcript (SC5).
3. Live: `bun scratchpad/live-http.ts <trusted scratch dir>` — starts a throwaway Claude,
   stops it via `POST /interrupt`, times `busy` dropping in `GET /api/sessions`.

## Implementation Phases

### Phase 1: Interrupt marks as a recency layer

- New `src/interrupt-marks.ts`: an in-memory mark per session — when the stop was
  confirmed, and the transcript size at that moment.
- `sessionTurnState` applies it last: a `running` verdict becomes
  `{ state: "idle", source: "interrupt" }` unless the hook spoke after the mark or a
  decisive transcript line was appended past the recorded size.
- `/api/sessions/:id/interrupt` records a mark only when `stopped === true`.

## Decision Log

- **A third recency layer, not a pane rule.** "Pane shows no spinner → idle" would cover
  terminal Escapes too, but a false idle mid-turn fires a "done" push and flickers the
  list. The pane is only trusted here once, at the moment lfg itself confirmed a stop.
- **Supersede on decisive bytes, not on mtime.** Claude appends `ai-title` and similar
  records after a turn opens; an mtime comparison would let those re-open the turn. The
  mark stores the transcript size and only a line `classifyTurnLine` calls decisive
  cancels it. Checked bytes are skipped on later ticks.
- **In-memory, not persisted.** A restart loses marks; `STALL_MS` still bounds the latch
  at 15 min. Persisting into the synced lease would leak a host-local judgement to the
  peer host.
- **The steering send path (`sendq.ts`) is untouched.** It types a new prompt right after
  its Escape, so the new turn's own records decide. Another session also has `sendq.ts`
  mid-edit.
- **Claude sessions only.** codex writes its own `turn_aborted` on a real stop, and its
  mid-turn records are not decisive, so a wrongly confirmed codex stop would be hidden
  for the rest of the turn (auditor R2). The endpoint gates on `sess.agent === "claude"`.
- **Accepted risks (auditor R1, R3).** R1: a prompt written in the few ms between the
  confirming capture and the synchronous note is hidden until the first reply. R3: a
  transcript that shrinks and regrows past its old size within one tick could hide a line;
  transcripts are append-only.
- **Not handled: Escape typed in the terminal itself.** lfg never sees it, so the label
  still waits for `STALL_MS`. Eugene sees the terminal directly in that case.

## Verification Evidence

Self-verification, 2026-10-04:

| SC | Command / action | Result |
|----|------------------|--------|
| SC1, SC2, SC3, SC4 | `bun test src/interrupt-marks.test.ts` | 9 pass, 0 fail |
| SC6 | `bun test src/session-state.test.ts src/turn-state.test.ts src/closing.test.ts src/journal-pump.test.ts src/push` | 208 pass, 0 fail across 13 files (`closing.test.ts` does not exist; Bun skipped it silently — corrected to `closing-actions.test.ts` below) |
| SC6 | `bunx tsc --noEmit -p .` | 0 errors |
| SC4 | Read `serve.ts` interrupt handler | mark recorded only inside `if (r.stopped === true)` |
| SC5 | `bun -e` probe on the real `b08adb88…` transcript with `now = 14:22:00Z` | without mark `{"state":"running","source":"transcript"}`; with mark at 14:21:31 `{"state":"idle","source":"interrupt"}` |
| Real seam | `scratchpad/stop-repro.ts`: real Claude in a scratch tmux pane, stopped 0.8s after submit via `interruptAndConfirm` + real tmux deps, then the endpoint's `noteConfirmedInterrupt` | `stopped:true`; no assistant row, no interrupt marker (root cause reproduced on a fresh session); verdict without mark `running`, with mark `idle`/`interrupt`, still idle 3s later; Enter resubmitted the rewound prompt (2nd user row) → `running`/`transcript` |

Independent audit #1 (`evidence/stop-clears-busy-audit.md`): **FAIL** on D1 — concurrent
readers in one tick both advanced `checkedSize`, leaving the mark past EOF so the next quiet
tick dropped it (20/20 trials). All other criteria PASS; 2,400 old-vs-new comparisons on 800
real transcripts with no mark: 0 mismatches.

Fix attempt 1 for SC3 (D1): advance from the read's own start with `Math.max`; Claude-only
gate for R2. New test "concurrent readers in one tick…" fails on the old `+=` line, passes on
the fix. `bun test src/interrupt-marks.test.ts src/session-state.test.ts src/turn-state.test.ts
src/closing-actions.test.ts src/journal-pump.test.ts src/push` → 236 pass, 0 fail, 15 files;
tsc 0 errors.

Independent re-audit: **PASS** — race probe idle 20/20 at every start offset (was running
20/20), suites 236/0, tsc 0, no-mark parity 2,400/0, R2 gate confirmed.

Fix for auditor R1 (steer flow): the endpoint takes `interruptBaseline()` BEFORE sending the
Escape, so a queued message that starts mid-confirm counts as "since the stop". New test "a
queued message that starts before the stop is confirmed → running"; 11/11 pass.

Full suite: 1,066 pass, 4 fail. The failures are `codex-bin.test.ts` (a Homebrew codex is
installed again on the Pro) and two 5s timeouts in `sessions-resumable-closed.test.ts`;
both fail identically on a clean worktree at HEAD.

**Live, through the running server (Pro, restarted 23:06:10 HKT):** `scratchpad/live-http.ts`
started a throwaway Claude, `POST /api/sessions/<id>/interrupt` at +9.3s →
`{"ok":true,"stopped":true}`; `/api/sessions` showed `busy:false` at +12.6s (3.3s, including
the list call's own latency); Enter resubmitted the rewound prompt → `busy:true` at +16.4s.
Transcript held only the two user rows: no assistant row, no interrupt marker — the exact
rewind case. Old code would have held `busy:true` for 15 min.

**Deploy:** the Pro server had run since 2026-10-01 22:42, so it already ran the dirty
`sendq.ts`/`turn-state.ts`; the restart added only my files (another session's new
`mcp-server.ts` is not imported by serve). The Air had run since 2026-09-28; its synced source
matched the Pro's byte for byte (7 files hashed), `bun install --frozen-lockfile` reported no
changes, restart 23:08:16 HKT under `serve-forever.sh`, 200 on `/api/sessions`, clean log.

## Bugs

_None open in scope._

## Observations (out of scope)

- **"Send now + interrupt" before the first reply may merge two prompts.** `sendq.ts`
  steers with the same `interruptAndConfirm`, then types the new message. If the stop
  rewinds, the old prompt is already back in the composer, so the typed text lands after
  it and both submit as one turn. Not reproduced; `sendq.ts` is mid-edit by another
  session, so it was left alone.
- **Escape typed in the terminal itself** still waits `STALL_MS`, because lfg never sees
  it (see Decision Log).
