# Verification Audit

Verdict: PASS
Timestamp: 2026-09-07 17:03 HKT (09:03Z)
Repository: /Users/eugenechan/dev/personal/lfg
Surface: mixed (unit tests + live API/log on the running Pro server)

## Change Audited

sendq recognises messages Claude Code absorbs mid-turn (`.claude/feature/sendq-absorbed-mid-turn.md`):
`queueOperationMessage` (src/sessions.ts) synthesises a user text turn from a `queue-operation
remove` line with a consumption reason; the journal pump hands every journaled user turn to
`noteSurfacedUserTurn` (src/sendq.ts) which promotes a matching `queued` row to `delivered`;
`reconcileQueued` re-drives only on sustained idle (`IdleConfirmer`), never while its delivery loop
runs, and never when the transcript window starts after the message was created (`windowStartTs`),
escalating to a rate-limited 4 MB deep read.

Running server: pid 33510, started 16:55:20 HKT, after the mtimes of sessions.ts (16:53:55),
sendq.ts (16:54:34), journal-pump.ts (16:54:38) — `00-server-process.log`.

## Success Criteria

| Criterion | Declared Method | Result | Evidence |
|-----------|-----------------|--------|----------|
| SC1 normaliser turns `queue-operation remove` + consumption reason into one user text turn with stable id + line ts; enqueue/dequeue/other reasons/`<`-content yield nothing | unit test `src/sessions-queue-operation.test.ts` | PASS | `01-sc1-sc4-unit-tests.log`: 7/7 pass in that file (25 pass / 0 fail across the two files) |
| SC2 queued row matching a newly journaled user turn promoted to `delivered` with journal `queue` ack, without waiting for reconcile | unit test `promoteSurfacedCore` + live `surfaced-delivered` within seconds | PASS | Unit: `01-sc1-sc4-unit-tests.log` (promoteSurfacedCore x3). Live: `04-sc2-sc5-sendq-log.jsonl` — ids `4ae10f63611a72f0`/`e396e143a987b893` `deliver-queued` 08:55:34Z, transcript `remove/absorbed_mid_turn` at 08:56:04.198Z (`08-…`), `surfaced-delivered` at 08:56:04.285/.287Z (87 ms later) with `userTurnId=queued:1788771364198:…`; journal acks `{"kind":"delivered"}` seq 933507/933509 (`09-sc2-journal-queue-acks.txt`) |
| SC3 no re-drive on a single idle capture; idle must hold ≥ IDLE_CONFIRM_MS and no delivery loop running | unit tests on `IdleConfirmer` | PASS | `01-sc1-sc4-unit-tests.log`: IdleConfirmer x4 pass (single capture false; confirms at 3000 ms; busy resets streak; per-session) |
| SC4 `reconcileQueuedCore` leaves a queued message untouched when window starts after its creation | unit test in `src/sendq.test.ts` | PASS | `01-sc1-sc4-unit-tests.log`: "transcript window coverage" x3 pass. Live corroboration: pre-fix row `1b654fd84bde2158` (created 08:41:52Z, absorbed 08:42:01Z under the OLD server) was outside the 40-message window (window start 08:55:17Z, `15-…`); on confirmed idle 4 s after the turn ended it was deep-scanned and marked `reconcile-delivered` (`13-…`, `18-…`), NOT re-driven |
| SC5 live: ≥2 messages queued into a busy Claude session; after the turn ends no `reconcile-pending`/`reconcile-failed`; transcript API returns them as user turns | sendq.log + `GET /api/sessions/:id/messages` | PASS | Session `5894849f…` was busy (`06-sc5-session-row.json`); turn ended 08:58:45.605Z (`turn_duration`, `16-…`); zero `reconcile-pending/failed` rows for any of the ids, and zero anywhere since restart (`18-…`); `GET …/queue` both `delivered` (`05-…`); `GET …/messages?limit=80` returns both as `role:user kind:text` ids `queued:1788771364198:7ec3c3677939db3d` / `…:8303977aa06863bd` (`07-sc5-messages-filtered.json`) |
| SC6 `bun test src/sendq*.test.ts src/sessions-*.test.ts src/recent-user-turns.test.ts src/journal-pump.test.ts` green | command output | PASS | `02-sc6-suite.log`: 176 pass / 0 fail across 21 files. Also `11-full-bun-test.log`: full `bun test` 780 pass / 0 fail; `10-resumable-tests-alone.log`: 15 pass; `03-tsc.log`: clean |

## Artifacts

- `00-server-process.log` — listener pid/start time vs source mtimes, launch PATH
- `01-sc1-sc4-unit-tests.log` — `bun test src/sendq.test.ts src/sessions-queue-operation.test.ts`
- `02-sc6-suite.log` — SC6 suite
- `03-tsc.log` — `bunx tsc --noEmit -p tsconfig.json`
- `04-sc2-sc5-sendq-log.jsonl` — sendq.log trace for the two live-check ids
- `05-sc5-queue.json` / `.headers` — `GET /api/sessions/:id/queue`
- `06-sc5-session-row.json` — session row (busy:true, tmuxTarget)
- `07-sc5-messages.json` / `07-sc5-messages-filtered.json` — `GET /api/sessions/:id/messages?limit=80` and the synthesised turns
- `08-sc5-transcript-queue-operation-lines.txt` — raw `queue-operation` lines in the transcript
- `09-sc2-journal-queue-acks.txt` — `~/.lfg/journal.db` `queue` events (read-only)
- `10-resumable-tests-alone.log`, `11-full-bun-test.log` — flaky-test check
- `12-sc2-auditor-post.log` — my own POST (id `3f8b4b7e05ac865e`)
- `13-sendq-rows-prefix-and-auditor.log` — trace for the pre-fix row and my row
- `14-journal-busy-around-reconcile.txt` — journal events around 08:58:49Z
- `15-recentMessages-window40-probe.txt` — what the 40-message window covers
- `16-sc5-turn-end-and-auditor-turn.txt` — transcript tail: turn end at 08:58:45Z, my message as a real user turn
- `17-pane-state-probe.txt` — `capture-pane` + `isBusy(pane)` + API busy
- `18-sc5-no-redrive-final-queue.txt` — no `reconcile-pending/failed`; final queue

## Commands

```
lsof -nP -iTCP:8766 -sTCP:LISTEN -t; ps -o pid,lstart,command -p <pid>; stat -f '%Sm %N' src/{sessions,sendq,journal-pump}.ts
bun test src/sendq.test.ts src/sessions-queue-operation.test.ts
bun test src/sendq*.test.ts src/sessions-*.test.ts src/recent-user-turns.test.ts src/journal-pump.test.ts
bun test src/sessions-resumable*.test.ts
bun test
bunx tsc --noEmit -p tsconfig.json
grep -E '4ae10f63611a72f0|e396e143a987b893' ~/.lfg/sendq.log
curl -s http://127.0.0.1:8766/api/sessions/5894849f-a36f-4b5c-8b25-acb10db35137/queue
curl -s 'http://127.0.0.1:8766/api/sessions/5894849f-a36f-4b5c-8b25-acb10db35137/messages?limit=80'
grep -n '"type":"queue-operation"' ~/.claude/projects/-Users-eugenechan-dev-personal-lfg/5894849f-a36f-4b5c-8b25-acb10db35137.jsonl
sqlite3 -readonly ~/.lfg/journal.db "select seq,ts,type,payload from events where sessionId='5894849f-…' and type='queue' order by seq desc limit 20"
curl -s -X POST -H 'content-type: application/json' -d '{"text":"auditor live check: …","clientId":"auditor-livecheck-…"}' http://127.0.0.1:8766/api/sessions/5894849f-…/send
bun -e 'import {recentMessages} from "./src/sessions.ts"; …recentMessages(path, 40)…'
tmux capture-pane -p -t lfg-3eb858:0.0 ; bun -e 'import {capturePane,isBusy} from "./src/tmux.ts"; …'
```

## Notes

- My own live sample hit the IDLE case: the parent turn had ended at 08:58:45Z, so
  `3f8b4b7e05ac865e` ran as a normal turn (`deliver-delivered` in 481 ms, real user uuid
  `e432444b`). It is not an absorption sample; the absorption evidence rests on the implementer's
  two rows, which I re-derived from sendq.log, transcript, journal.db and the API independently.
- The pre-fix row `1b654fd84bde2158` is the most discriminating live evidence: absorbed under the old
  server, outside the 40-message window, aged 17 min, session idle-confirmed. Old code would have
  emitted `reconcile-pending` (re-typed); new code emitted `reconcile-delivered` via the deep scan.
- Full `bun test` passed 780/0 here; the 4 `sessions-resumable*` failures the implementer saw
  during the server restart did not reproduce (alone: 15/0; in the full suite: 0 fail). Consistent
  with timing flakes under load, not a regression from this change.
- Out of scope: `GET /api/sessions` reports `busy: true` for the session while the pane reads idle
  (`isBusy(pane)=false`, composer visible, "Waiting for 1 background agent") and the transcript
  shows a finished turn (`17-pane-state-probe.txt`). Does not affect any criterion here.
- Read-only constraints honoured: no restarts, no sends to other sessions, one POST to the
  permitted session, no git mutations, no source edits.
