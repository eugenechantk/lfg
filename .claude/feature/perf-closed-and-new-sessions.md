# Feature: fast closed sessions and fast new-session pickup

## User Story

As Eugene, I want the Closed/Recent list to load in a couple of seconds and a session started anywhere (terminal, scheduled task, another device) to show up in the phone's list within seconds, so that the app feels live.

## The two problems (measured 2026-10-16)

1. **Closed sessions are slow.** `GET /api/sessions/resumable` takes 17–23 s on the Pro, on every page. In-process on the same corpus it takes 4.3–5.6 s:
   - refreshing leases for live sessions: ~3 s (it lists live sessions uncached);
   - `codexThreads()`: 1.3–2.4 s;
   - everything else: ~0.2 s.
   The busy server stretches this about four times.
   `codexThreads()` reads the head of all 1,041 codex rollouts on every call: 128 KB for the header line, then up to 1 MB more for the first user message (`firstUserTextFromTop`). Both never change once written. The live-session list calls `codexThreads()` too, so the lease step pays it again, and so do search and subagent lookups.
2. **New sessions show up late on the phone.** A session that asks a question at once emits `busy` and `prompt` events but no message until answered. The phone refreshes its list for an unknown session's *message* events only, so the row appears at the next 60 s refresh (75 s observed). The desktop polls every 10 s and is not affected.

## Success Criteria

- [x] SC1: The first page of `GET /api/sessions/resumable` returns in ≤ 3 s on the live Pro, and a later page too (from 17–23 s). — **Verify by:** three timed curls each, after deploy.
- [x] SC2: The closed list's content does not change: same ids, order, titles, cwd and model as before. — **Verify by:** in-process A/B of `listResumable` (old vs new code) on the same corpus; unit tests for the memo (a file that grows, a header written late, a deleted file, a replaced file).
- [x] SC3: The live list's codex rows do not change. — **Verify by:** existing codex binding tests; `/api/sessions` codex rows before/after on the live Pro.
- [x] SC4: A session started outside the phone, whose first events are `busy`/`prompt`, appears in the phone's list within 10 s of its first event. — **Verify by:** live in the simulator: create a session through the API that asks at once; time until its row shows.
- [x] SC5: An event for a session that stays unknown cannot cause a refresh storm: at most 3 refreshes per unknown session, at least 5 s apart. — **Verify by:** LFGCore unit tests for the policy.
- [x] SC6: bun and LFGCore suites green; no regression in send, answer or Live Activity. — **Verify by:** suites; one live send + answer.

## Plan

- **Server:** memoise each rollout's header and first user message by path, invalidated by birth time or a shrink. The first user message counts as final once the file reaches the 1 MB read window. Re-measure after it, and only then decide whether the lease step needs its own change.
- **Phone:** an `UnknownSessionRefresh` policy in LFGCore: any session-scoped event (`msg`, `busy`, `prompt`, `queue`) for an unknown, non-local id may trigger a refresh. That's at most 3 tries per id, 5 s apart, one in flight. `SessionStore.applyIngested` uses it.
- **Ship:** both servers, then a TestFlight build for the phone change.

## Decision Log

- 2026-10-16 — "Slow start session" read as the late appearance of new sessions in the phone list (the gap reported after Phase 5), not the create call, which returns at once.

## What changed (2026-10-16)

Server, four commits, deployed to the Pro and the Air:

1. `src/codex-rollout-memo.ts`: each rollout's header and first user message are read once (append-only files; a new birth time or a shrink means a new file). In-process: closed first page 4.4 s → 1.5 s, live list 4.1 s → 1.6 s, output identical.
2. The closed list reuses the pump's session scan instead of running its own (`sharedListSessions`, which never starts a scan; a cold process keeps the lightweight private scan).
3. `anyFreshAt` rules out a lease by file mtime before reading it (window + 5 min skew slack); the last finished scan is used when under 5 s old, so no request waits on one.
4. The 27 live leases refresh concurrently: serial awaits on the busy loop cost 1.2–3.6 s for 0.2 s of work.
Plus a `Server-Timing` header on the route (leases, candidates, fill, enrich, total, scan-shared/private), which is how steps 3 and 4 were found on the live server without a profiling build.

Phone: `UnknownSessionRefresh` in LFGCore and its use in `SessionStore.applyIngested`.

## Verification Evidence

| SC | Check | Result |
|---|---|---|
| SC1 | Live Pro, `Server-Timing` total, after the last deploy | first page 1.2 / 2.1 / 1.2 s; later page 0.42 / 0.38 s; hidden-folder page 1.1 / 1.4 s (was 17–23 s). Air: 0.46 / 0.19 / 0.14 s |
| SC2 | In-process A/B old vs new on the real corpus, three page shapes | 30/30, 30/30, 60/60 rows identical (id, title, cwd, model, agent, last text); `codex-rollout-memo.test.ts` 6 tests |
| SC3 | Live codex rows old vs new, three runs in both orders | 17 = 17 each time, no row only on one side |
| SC4 | Live, simulator, fresh S2 build: session created by API that asks at once | server `prompt` event 17:53:08.4, row in the list 17:53:11.7 (3.3 s; 2 s poll). Before: 75 s. `evidence/perf-closed-and-new-sessions/new-session-listed-3s.png` |
| SC5 | `UnknownSessionRefreshTests` | 6 tests: event kinds, first event, known/in-flight/local never, 5 s spacing, 3-try cap, forget |
| SC6 | Suites + live | bun 1,251/1,251 (`--timeout 60000`); LFGCore 644 XCTest + 421 Swift Testing. Live answer in the app cleared the panel and drew "You picked Coffee." (`answered.png`) |

Deploys: Pro restarted five times today on this work (last pid 12716, under `serve-forever.sh`); Air at `be03125` (pid 65931). TestFlight **202610161755** (v1.3.0) from `3d3ded9`: VALID on train 1.3.0, internal IN_BETA_TESTING (`ios/fastlane/deploy-202610161755.log`, `verify-202610161755.log`).

Status (2026-10-16): **done and shipped.** Server on both hosts, phone on TestFlight.

Found on the way: `bun test` without `--timeout` is killed (exit 137) on this machine when `sessions-resumable-closed.test.ts` runs against the real corpus with the full-enrichment scan — about 1.1 GB RSS. The lightweight scan keeps it at ~0.6 GB. The two tests still read the real corpus; a fixture root is the proper fix (improvement log).

## Bugs

_None yet._
