# Feature: sendq recognises messages Claude absorbs mid-turn

Diagnosis: `.claude/diagnosis-queued-messages-absorbed-mid-turn-20260907.md`.

## User Story

As Eugene sending several messages from the phone while an agent is mid-turn, I want each one to
show as delivered (and stay visible in the transcript) once Claude has taken it, so that I am not
told to resend messages the agent already has — and so the agent does not receive each of them
two or three times.

## User Flow

1. Agent is busy. Eugene sends messages A, B, C from the iOS client.
2. Each lands in Claude Code's native queue (`deliver-queued`). Claude absorbs them into the running
   turn at the next tool boundary (`queue-operation remove / absorbed_mid_turn`).
3. lfg marks each `delivered` within a pump tick of absorption; the pending bubble retires and a
   user bubble for the text appears in the transcript at the absorption point.
4. The turn ends. Nothing is re-typed, nothing is marked failed.
5. A message Claude genuinely dropped (Escape'd, edited away) still gets re-driven — but only after
   the session has been idle for a sustained window, and not while lfg itself is typing.

## Success Criteria

- [x] SC1: `normalizeLineMessages` turns a `queue-operation` line with `operation:"remove"` and a
  consumption reason (`absorbed_mid_turn`, `delivered_to_agent`, `delivered_as_tool_result`) into
  one `{role:"user", kind:"text"}` message with a stable synthetic id and the line's timestamp;
  `enqueue`, `dequeue`, other reasons, and internal `<task-notification>`-style content yield
  nothing. — **Verify by:** unit test `src/sessions-queue-operation.test.ts`.
- [x] SC2: A `queued` sendq row whose text matches a newly journaled user text turn is promoted
  to `delivered` (journal `queue` ack `kind:"delivered"`) without waiting for `reconcileQueued`.
  — **Verify by:** unit test on the pure promotion core in `src/sendq.test.ts` + a live check
  (send to a busy session, watch `sendq.log` show `surfaced-delivered` within seconds).
- [x] SC3: `reconcileQueued` does not re-drive on a single idle capture: idle must be observed
  continuously for ≥ `IDLE_CONFIRM_MS` and no delivery loop may be running for that session.
  — **Verify by:** unit tests on the pure `IdleConfirmer` in `src/sendq.test.ts`.
- [x] SC4: `reconcileQueuedCore` leaves a queued message untouched when the transcript window it
  was given starts after the message was created (cannot prove absence). — **Verify by:** unit test
  in `src/sendq.test.ts`.
- [x] SC5: Live: on the Pro host, with the fixed server running, queue ≥2 messages into a busy
  Claude session; after the turn ends `sendq.log` shows no `reconcile-pending`/`reconcile-failed`
  for them and the transcript API returns them as user turns. — **Verify by:** `sendq.log` +
  `GET /api/sessions/:id/messages` output recorded below.
- [x] SC6: Existing suites stay green: `bun test src/sendq*.test.ts src/sessions-*.test.ts
  src/recent-user-turns.test.ts src/journal-pump.test.ts`. — **Verify by:** command output.

## Platform & Stack

- **Platform:** Backend (Bun server), consumed by the iOS client unchanged
- **Language:** TypeScript
- **Key files:** `src/sessions.ts` (normaliser), `src/sendq.ts`, `src/journal-pump.ts`

## Steps to Verify

1. `bun test <files>` for SC1–SC4, SC6.
2. Restart the Pro server by port (`lsof -nP -iTCP:8766 -sTCP:LISTEN -t`), confirm new start time.
3. SC5: pick a busy Claude session, `POST /api/sessions/:id/send` twice, tail `~/.lfg/sendq.log`,
   then read the transcript page.

## Implementation Phases

### Phase 1: Normaliser (SC1)
- Scope: `normalizeLineUnsafe` accepts `type:"queue-operation"`.
- Gate: new unit test green, existing sessions tests green.

### Phase 2: sendq promotion + guarded reconcile (SC2–SC4)
- Scope: `noteSurfacedUserTurn` (pure core + exported hook), `IdleConfirmer`, `windowStartTs`
  guard, pump call-site.
- Gate: sendq tests green.

### Phase 3: Deploy + live check (SC5)

## Decision Log

- **Synthesise the user turn in the normaliser rather than special-casing sendq.** One change
  makes the absorbed message visible in every consumer (iOS transcript, previews, sendq, pending
  strip) instead of patching each. Alternative: teach only sendq to read `queue-operation`; rejected
  because the phone would still show the message vanishing.
- **Synthetic id = `queued:<ts>:<hash(content)>`.** `queue-operation` lines carry no `uuid`; the
  client dedups on id across stream replays, so a stable id is needed.
- **Consumption reasons = the three `consume(...,{reason})` strings in the 2.1.259 binary.** Any
  other/unknown reason is treated as "not delivered" so a genuinely dropped message still re-drives.
- **Skip content starting with `<`.** Claude Code enqueues its own `<task-notification>` poll
  events through the same queue; they are not conversation (matches the existing `<`-prefix rule
  in `recentUserTurns`).
- **Sustained idle via per-session first-idle timestamp, not a sleep.** `reconcileQueued` runs in
  the pump's poll; sleeping there would stall the sweep, which already takes 10–17 s.
- **Unknown-window ⇒ leave queued, plus a rate-limited deep read (4 MB, ≥30 s apart).** A stuck
  "queued" row is visible and dismissable; a duplicated instruction to the agent is not undoable.
- **Not touching Cloudflare 502s.** They are restart windows from other deploys; out of scope.

## Verification Evidence

All run 2026-09-07 16:50–17:00 HKT on the Pro (`Eugenes-MacBook-Pro`), server pid 33510 started
16:55:20 HKT with this working tree.

| SC | Command / action | Observed |
|----|------------------|----------|
| SC1 | `bun test src/sessions-queue-operation.test.ts` | 7 pass: absorbed remove → `{role:user, kind:text, ts}`; stable distinct ids; 3 consumption reasons accepted; enqueue/dequeue/other-reason/`<task-notification>`/blank → `[]`; `recentMessages` places the turn between the tool_use and its tool_result |
| SC2 | `bun test src/sendq.test.ts` (promoteSurfacedCore ×3) + live | Tests pass. Live: `sendq.log` ids `4ae10f63611a72f0`/`e396e143a987b893`: `deliver-queued` 08:55:34Z → `surfaced-delivered` 08:56:04.285Z with `userTurnId=queued:1788771364198:…`; transcript `queue-operation remove absorbed_mid_turn` for both at 08:56:04.198Z (87 ms earlier); `journal.db` has `queue {"kind":"delivered"}` acks for `livecheck-A/B-1788771332`; `GET /api/sessions/5894849f…/queue` → both `delivered` |
| SC3 | `bun test src/sendq.test.ts` (IdleConfirmer ×4) | pass: single capture ≠ confirmation; confirms at ≥3 s; busy resets streak; per-session |
| SC4 | `bun test src/sendq.test.ts` (window coverage ×3) | pass: uncovered window → untouched; covered → re-driven; surfaced wins regardless |
| SC5 | Two `POST /api/sessions/5894849f-a36f-4b5c-8b25-acb10db35137/send` into this busy Claude session at 08:55:32Z | No `reconcile-pending`/`reconcile-failed` for either id; `GET …/messages?limit=80` returns both as `role:user kind:text` ids `queued:1788771364198:7ec3c3677939db3d` / `…:8303977aa06863bd`; the agent (this session) received both mid-turn |
| SC6 | `bun test` (whole suite) | Run 1 (during the server restart): 776 pass / 4 fail in `sessions-resumable*.test.ts` (one at the 5000 ms timeout). Same files alone: 0 fail. Run 2 (quiet host): **780 pass / 0 fail**. Classified as timing flakes unrelated to this change. `bunx tsc --noEmit -p tsconfig.json`: clean |

Independent audit: `verification-auditor` → **PASS on all six criteria**, evidence in
`.claude/evidence/20260907-165759-sendq-absorbed-audit/` (22 artifacts, report `evidence.md`). Its most
discriminating finding: the pre-fix row `1b654fd84bde2158` (absorbed at 08:42:01Z under the OLD server,
17 min outside the 40-message window) was promoted by the deep-read path with a synthesised
`userTurnId` four seconds after the turn ended — the old code would have re-typed it. Its own live
sample hit the idle case (normal turn, `deliver-delivered` in 481 ms), so the absorption evidence rests
on the implementer's two rows, which it re-derived independently from sendq.log, the transcript,
journal.db and the API. Out-of-scope note: `/api/sessions` reports `busy:true` while a session waits on
a background agent even though the pane reads idle — that is `busyWithRunningWork` counting child
agents by design, not a regression.

## Deployment notes

- Pro: restarted by port at 16:55:20 HKT (old pid 84261 → 33510). During the ~2 s respawn Cloudflare
  answers 502 — that is the 502 Eugene sees when a resend coincides with any restart.
- Air: still running the old code until this is committed and deployed there (not committed — no
  instruction to commit).
- Queue rows that were absorbed *before* the restart (e.g. `1b654f…` on this session) are recovered
  as `queued`; on the next sustained idle the reconcile's deep read (4 MB) finds their synthesised
  turn and promotes them instead of re-driving.

## Bugs

_None yet._
