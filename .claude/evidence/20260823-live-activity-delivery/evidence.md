# Verification Audit

Verdict: PARTIAL (SC1–SC4 PASS; SC5 PARTIAL — server-initiated debounced end not yet observed live; residual risk judged acceptable)
Timestamp: 2026-08-23 16:14 HKT (08:14Z)
Repository: /Users/eugenechan/dev/personal/lfg
Surface: api/backend (Bun server, APNs push watcher)

## Change Audited

Uncommitted working-tree changes to `src/push/apns.ts`, `src/push/watcher.ts`,
`src/push/liveactivity-store.ts` (+ tests): HTTP/2 session pooling with 10s
timeout and one transient retry; all-accepted advancement for update/end Live
Activity pushes; 60s fleet-empty end debounce (`zeroSince`); pushToStart token
cap (newest 3 per env); `client-ended`/`adopted` trace lines.
Feature doc: `.claude/feature/live-activity-delivery-reliability.md`.

## Success Criteria

| Criterion | Declared Method | Result | Evidence |
| --- | --- | --- | --- |
| SC1 transport pool + transient retry | unit tests; live soak of status:0 rate | **PASS** (soak pending by design) | `01-push-suite.log` (90/90); `04-mutation-audit.log` Mutation C (no-retry revert → 2 tests fail); `06-deploy-check.log` (2 ESTABLISHED conns to 17.188.x.x:443 held open — old code closed per send); post-deploy sends 15, status:0 = 0 (`07-live-log-post-deploy.jsonl`; baseline 690/22,433 — sample too small, soak PENDING per doc) |
| SC2 all-accepted advancement for update/end; start keeps sent>0 | unit tests driving `runPushTick` with a fake transport failing one of two tokens | **PASS** | `03-new-tests-vs-old-code.log` (tests unrunnable against HEAD); `04-mutation-audit.log` Mutation A (`required = 1` revert → both update & end partial tests fail; start test correctly unaffected) |
| SC3 60s end debounce, zeroed update during hold, reappearance cancels | unit tests on `reduceFleetLiveActivity` stepping `now` | **PASS** | `04-mutation-audit.log` Mutation B (`FLEET_END_DEBOUNCE_S = 0` → all 5 debounce tests fail); `05-zerosince-roundtrip.log` (zeroSince survives fleet-active-store JSON round-trip; save(null) clears); live: `07-live-log-post-deploy.jsonl` 08:08:05Z fleet-empty tick → zeroed `update` (working 0, rows []), not an end |
| SC4 pushToStart cap 3/env at write and read | unit tests; live `decide` tokens ≤ 6 | **PASS** | `03-new-tests-vs-old-code.log` (3 cap assertions fail on real behavior against HEAD code — evict-4th, per-env, read-time cap); live: 08:08:59Z `start` → **5 tokens** (2 prod + 3 sandbox), previously 13–19 |
| SC5 deployed; watcher alive; new log shapes | ps start time vs mtime + live log | **PARTIAL** | `06-deploy-check.log`: PID 57652 started 16:10:06 > newest mtime 16:09:59 (watcher.ts); runtime proof of new code: `client-ended`/`adopted` events (new-code-only) in log from 08:10:45Z on; zeroed-update-on-empty observed; **0 server `end` decides post-deploy** (no immediate end→start flap). NOT observed: the full zeroed-update → ≥60s → server `end` sequence — the shipped client's own end-reports (`client-ended` every ~30–60s) null the card before the window expires |

## Artifacts

All in `/Users/eugenechan/dev/personal/lfg/.claude/evidence/20260823-live-activity-delivery/`:

- `01-push-suite.log` — `bun test src/push/`: 90 pass / 0 fail, 186 assertions
- `02-full-suite.log` — `bun test`: 715 pass / 0 fail
- `03-new-tests-vs-old-code.log` — new test files run against a HEAD worktree: watcher/apns tests fail at import (exports absent pre-change); 3 store-cap tests fail on assertions
- `04-mutation-audit.log` — three behavior reverts applied to CURRENT code in a scratch worktree; every mutation killed by the new tests (A: 2 fail, B: 5 fail, C: 2 fail)
- `05-zerosince-roundtrip.log` — runtime probe: `zeroSince` persists through `saveFleetActivityActive`/`loadFleetActivityActive` (scratch state file via `LFG_FLEET_ACTIVITY_STATE`)
- `06-deploy-check.log` — PID/start time, source mtimes, pooled APNs connections
- `07-live-log-post-deploy.jsonl` — `~/.lfg/liveactivity.log` excerpt 08:04Z→08:14Z

## Commands

```
bun test src/push/                      # 90 pass
bun test                                # 715 pass
git worktree add <scratch>/head-worktree HEAD   # old-code + mutation runs (removed after)
LFG_FLEET_ACTIVITY_STATE=<scratch>/fleet-state-probe.json bun <scratch>/zerosince-roundtrip.ts
lsof -nP -iTCP:8766 -sTCP:LISTEN -t     # → 57652
ps -p 57652 -o pid,lstart,command; stat -f "%Sm %N" src/push/{apns,watcher,liveactivity-store}.ts
lsof -nP -p 57652 | grep '\->17\.'      # 2 pooled APNs conns
awk '/2026-08-23T08:0[4-9]|08:1[0-9]/' ~/.lfg/liveactivity.log
```

Mutations (each applied alone in the scratch worktree, then reverted):
A `watcher.ts:569` `required = attempted` → `1`; B `watcher.ts` `FLEET_END_DEBOUNCE_S = 60` → `0`;
C `apns.ts` `sendWithTransientRetry` early-return check removed.

## Notes

Defects / residual risks found (none blocks a criterion):

1. **Timeout does not evict the pooled session** — `apns.ts:192–195` cancels the
   stream and resolves status 0, but leaves the (possibly wedged) session in
   `apnsSessions`; the transient retry and every later send reuse it, each
   eating 10s until a TCP-level error fires. Worst case one 2-token decision
   stalls the (skip-while-running) tick loop ~40s. Suggest dropping the session
   from the pool on timeout. Minor.
2. **Rare session leak** — `apns.ts:189`: if `session.request` throws, the
   session is deleted from the pool without `close()`. Minor.
3. **Non-410 permanent rejection livelock** — `watcher.ts:569–577`: a token that
   permanently answers a non-410/non-transport status (e.g. 400
   `DeviceTokenNotForTopic`, 403 `InvalidProviderToken`) is never pruned by
   `isDeadApnsToken` (`watcher.ts:451`), so update/end never reach all-accepted
   and the reducer re-decides every 2s tick indefinitely (~1 send/s, ~130k
   trace lines/day). Rate-bounded, duration-unbounded; the code comment accepts
   this for 410s but non-410 permanent rejections exist. Worth a cap or pruning
   on repeated identical 4xx.
4. **Pre-existing race, now visible in the trace** — captured live at
   08:11:36.550–.781Z: `client-ended` (`watcher.ts:708`) landed between a
   tick's `decide` and its sends; `applyLiveActivityDecision` then set
   `active.current = nextActive` (`watcher.ts:579`), clobbering the client's
   end. Server keeps zero-updating (and would eventually re-end) an activity
   the client already ended — harmless churn, same overwrite existed pre-change.
5. **SC4 residual (by design, documented)** — a real device on a sandbox/dev
   build can have its pushToStart token evicted by 3 later simulator
   registrations in the same env; production (TestFlight) tokens are protected
   per-env.
6. **Debounce clock nuance** — if the zeroed update partially fails, state does
   not advance, so `zeroSince` is effectively recorded only once the zeroed
   update fully delivers; the 60s window starts from that acceptance.
   Conservative (card lingers), not a defect.

SC5 residual-risk judgement: **acceptable**. The unobserved piece (server
`end` after 60 continuous empty seconds) is mutation-verified at the reducer
and advancement seams; the reason it cannot yet be seen live is the documented
out-of-scope client half (shipped 1.2.0 latches busy / ends its own card —
`client-ended` churn every ~30–60s in the log). Its failure mode if broken is a
lingering zeroed card, strictly better than the pre-change zombie. Re-check the
log for a `decide end` with all-200s once the client fix ships, alongside the
SC1 status-0 soak (~1 day).

Discrepancy vs implementer's claims: they reported PID 43994 (16:03:54); the
server was restarted again (watcher.ts touched 16:09:59 — the trace lines) and
now runs as PID 57652 (16:10:06). Deploy claim still holds: process > mtimes,
and new-code-only log events prove the running binary.
