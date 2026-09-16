# Verification Audit

Verdict: PARTIAL
Timestamp: 2026-09-15 17:25 HKT (09:25 UTC)
Repository: /Users/eugenechan/dev/personal/lfg
Surface: mixed (Bun server unit tests, LFGCore Swift package tests, iOS app build product, recorded live seam via stub host)

PARTIAL means: SC1–SC5 were each checked and hold. SC6 (forced resume over a fresh foreign lease on the real server) is unverifiable without restarting the long-lived `lfg serve` on :8766, which the feature doc's Decision Log defers to Eugene and which this audit was instructed not to do. No checked criterion failed.

## Change Audited

Uncommitted working-tree change "transfer-from-offline-host":

- `ios/LFG/SessionStore.swift` — `transfer(_:to:)` now derives a `SessionTransfer.Plan`; when the source host is known down (`!isNotKnownDown`) or the close throws a transport-level `LFGError`, the close is skipped, the target is asked to resume with `force: true`, and the source-side close is remembered in `DeferredSourceCloses` (UserDefaults key `lfg.deferredSourceCloses`) and replayed from `setHostState` (`replayDeferredSourceCloses`) when that host next becomes live. `close(_:)` forgets a pending deferred close for the id.
- `ios/LFGCore/Sources/LFGCore/SessionTransfer.swift` (new) — `SessionTransfer.plan`, `closeFailureIsUnreachable`, `DeferredSourceCloses`.
- `ios/LFGCore/Sources/LFGCore/Models.swift` — `ResumeRequest.force`; `LFGClient.resume` sends it.
- `src/commands/serve.ts` — exported `foreignLeaseVeto(sessionId, force)`; `resumeClosedSession({force})`; route reads `body.force === true`.
- Tests: `ios/LFGCore/Tests/LFGCoreTests/SessionTransferTests.swift`, `src/commands/serve-resume-force.test.ts`.

Note: the `SessionStore.swift` diff (+635 lines) and `serve.ts` diff also carry unrelated concurrent work (codex resume bootstrap watch, resumable `exclude`, `childAgents`); only the transfer/force/deferred-close portions were audited.

## Success Criteria

| Criterion | Declared Method | Result | Evidence |
|---|---|---|---|
| SC1 — Known-down source: skip close, resume on target with force | `SessionTransferTests` (`sourceKnownDown: true` → `closeSource == false`, `force == true`) + code path in `SessionStore.transfer` | PASS | `01-swift-test-SessionTransferTests.log` — `testKnownDownSourceSkipsCloseForcesResumeAndDefersClose` passed (7/7). Code path: `SessionStore.swift:4336` builds the plan from `!isNotKnownDown(source)`; `isNotKnownDown` (line 606) is `!showsOfflineBanner`, and `HostState.showsOfflineBanner` (HostState.swift:70-74) is true only for `.offline`/`.noNetworkSustained` — exactly the states SC1 names. Lines 4337-4352 skip the close when `plan.closeSource` is false; line 4376 sends `force: plan.force ? true : nil`. Live seam: `05-live-stub-host.log` shows no request of any kind reached the stub between 09:12:05Z (last ping) and 09:16:22Z (stub back), while `06-sc1-s9-detail-offline.png` (17:14 HKT) shows the offline notice on the source and `07-sc1-s12-after-move.png` (17:15 HKT) shows the same conversation now on `Eugenes-MacBook-Pro`; `09-live-tmux-before-after-final.txt` shows a new pane `lfg-ac573b` on the Pro after the move. |
| SC2 — Transport-level close failure still proceeds; HTTP error aborts | `SessionTransferTests.testCloseFailureClassification` | PASS | `01-swift-test-SessionTransferTests.log` — `testCloseFailureClassification` passed: `notReachable`/`transport` → true; `http(404)`, `http(500)`, `decoding`, non-LFGError → false. Wiring: `SessionStore.swift:4339-4351` — `catch where SessionTransfer.closeFailureIsUnreachable(error)` flips `plan = .sourceUnreachable`; any other error sets `lastError` and returns nil. (Not exercised live; unit-level only, as declared.) |
| SC3 — Server resume accepts `force`, bypasses 409 over a fresh foreign lease; still 409s without it | `src/commands/serve-resume-force.test.ts` against a fixture lease | PASS | `03-bun-test-resume-force.log` — 27 pass / 0 fail across `serve-resume-force.test.ts`, `leases.test.ts`, `serve-fork.test.ts`; the forced-override log line `[resume] … forced over fresh lease held by peer-host-that-is-asleep` is printed. Tests: fresh lease → 409 + `liveOn`; `force` → null; no lease → null either way. `04-tsc-noEmit.log` — `npx tsc --noEmit -p .` exit 0, zero diagnostics. Route wiring in the diff: `body?.force === true` → `resumeClosedSession({force})` → `foreignLeaseVeto(sessionId, opts.force === true)`. |
| SC4 — Skipped close is remembered (persisted) and executed once the source is live again | `SessionTransferTests` for `DeferredSourceCloses` (add / take / codable) + wiring in `SessionStore.setHostState` | PASS | `01-swift-test-SessionTransferTests.log` — `testDeferredClosesAddIsIdempotentAndTakeIsOneShot`, `testDeferredClosesForgetDropsSessionEverywhere`, `testDeferredClosesRoundTripAndTolerateGarbage` passed. Wiring: `SessionStore.swift:384-390` persists on `didSet` to UserDefaults and decodes at init; `1872-1876` calls `replayDeferredSourceCloses(forHost:)` on the `!wasLive && settled.isLive` transition; `1885-1901` takes the owed ids and closes via `settings.client(for: host)` where `host` is looked up by id (source host, not `client(forSession:)`). Live seam: `05-live-stub-host.log` — stub back 09:16:22Z; first successful `GET /api/sessions` 09:18:58.822Z; `POST /api/sessions/50980bea-…/close` at 09:18:58.876Z (54 ms later) followed by `CLOSE 50980bea-…`. The close landed on the stub (port 8799, the source), not on the Pro (the new owner). |
| SC5 — Reachable source: unchanged — close, wait loop, resume without force; `swift test` green; iOS app builds | `SessionTransferTests` (`sourceKnownDown: false`) + `swift test` green + iOS app builds | PASS | `01-…log` — `testReachableSourceClosesFirstAndDoesNotForce` passed. `02-swift-test-full.log` — 516 tests, 1 skipped, 0 failures, exit 0. Diff vs HEAD (`git show HEAD:ios/LFG/SessionStore.swift`, old lines 3949-4005) — the close (4338), the 8×400 ms disappearance wait (4355-4359), and the 10×700 ms `alreadyLive` retry (4379-4384) are byte-identical; the only change on the reachable path is `force: nil` (the wire dict encodes it as `null`, which the server reads as not-forced). iOS build: `10-sc5-ios-build-binary-strings.log` + FlowDeck log `~/.flowdeck/logs/734d3b6e4105/build.log` — `BUILD SUCCEEDED` at 17:19:45 for `/Users/eugenechan/dev/personal/lfg/ios/LFG.xcodeproj` (after the final `SessionStore.swift` mtime 17:13:02); its `LFG.debug.dylib` contains `lfg.deferredSourceCloses`, `skipping close (deferred)`, `close unreachable`, `orphaned source copy`, `still sees this session running`, `replayDeferredSourceCloses`. |
| SC6 — Live: forced resume over a fresh foreign lease on the real server | curl `POST /api/sessions/resume` with `force:true` against a fixture lease | NOT VERIFIED | The :8766 server (pid 41409) started 16:05:13, before `src/commands/serve.ts` was modified at 17:00:14, so it runs the pre-`force` code; restarting it is out of scope for this audit and deferred to Eugene per the Decision Log. The other running server (pid 57499, :9982) is the `.worktrees/ios-terminal` tree, which has no `foreignLeaseVeto` (grep count 0). The live stub run does not cover SC6 either: the stub writes no lease file, so the target's veto never fired regardless of `force`. |

## Code review against the caller's checklist (a)–(e)

All in `/Users/eugenechan/dev/personal/lfg/ios/LFG/SessionStore.swift`:

- (a) Deferred close recorded only after a successful target resume — HOLDS. `deferredSourceCloses.add(host: source.id, session: id)` is at line 4394, after the `alreadyLive` retry loop (4379-4384), after the "couldn't take over" early return (4385-4389), and inside the `do` — the `catch` (4400-4410) never adds.
- (b) Deferred close sent to the SOURCE host's client — HOLDS. `replayDeferredSourceCloses` (1885-1901) resolves `settings.hosts.first(where: { $0.id == hostId })` then `settings.client(for: host)`; `client(forSession:)` is not used. The stub log confirms the close hit the source (port 8799) after the session had been re-pointed to the Pro.
- (c) `force` only when the plan says the source is unreachable — HOLDS. Line 4376: `ResumeRequest(sessionId: id, force: plan.force ? true : nil)`; `plan.force` is true only for `Plan.sourceUnreachable`, reached via known-down (4336) or transport-failed close (4345).
- (d) Reachable path unchanged — HOLDS. See SC5 row; compared against `git show HEAD:…` lines 3958-3993.
- (e) Manual `close(_:)` forgets the pending deferred close — HOLDS. Lines 4066-4070: `deferredSourceCloses.forget(session: id)` before `run("End session", …)`.

No logic bug found in the audited paths.

## Live-seam log reconciliation (caller's item 5)

`05-live-stub-host.log` (UTC; local = UTC+8):

| Claimed step | In the log? | Note |
|---|---|---|
| stub up | 09:07:12Z, restarted 09:11:40Z | yes |
| killed 09:12:12Z | not directly — a kill does not log | last served request 09:12:05.639Z; the next line is `stub up` at 09:16:22Z. Consistent with a kill at ~09:12:12Z, and the 4-minute silence is the outage. |
| app moved at ~09:15:40Z with no close reaching the stub | nothing reaches the stub between 09:12:05Z and 09:16:22Z | `07-sc1-s12-after-move.png` mtime 17:15 HKT (09:15Z); `tmux-after.txt` 17:16 HKT shows new pane `lfg-ac573b` on the Pro |
| stub back 09:16:22Z | yes | `/api/ping` and `/api/events` 404 (stub does not implement them), so the host only reads as live once `GET /api/sessions` succeeds |
| `POST …/close` at 09:18:58Z right after the first successful `GET /api/sessions` | yes — `GET /api/sessions` 09:18:58.822Z, `POST /api/sessions/50980bea-…/close` 09:18:58.876Z, `CLOSE 50980bea-…` | replay fired on the host-live transition |

This sequence supports SC1 (close skipped while the source was known down; resume on the target proceeded) and SC4 (the close was deferred and executed on the source host once it was live again). Two caveats: (1) the app was not restarted between the move and the replay, so the "persisted across app restarts" half of SC4 is covered only by the codable round-trip unit test and the `didSet` UserDefaults write, not by the live run; (2) the live run exercised the 17:07:22 build, which predates the final `SessionStore.swift` edit (17:13:02) — that build already contained the skip-close / deferred-close / replay strings but not `still sees this session running`, so the 409-specific error copy (and possibly other detail in that last edit) was not what ran live. The final source was compiled successfully at 17:19:45.

## Artifacts

All under `/Users/eugenechan/dev/personal/lfg/.claude/feature/evidence/transfer-from-offline-host/`:

- `01-swift-test-SessionTransferTests.log` — `swift test --filter SessionTransferTests`: 7 tests, 0 failures, exit 0
- `02-swift-test-full.log` — `swift test`: 516 tests, 1 skipped, 0 failures, exit 0
- `03-bun-test-resume-force.log` — 27 pass / 0 fail, exit 0
- `04-tsc-noEmit.log` — exit 0, no diagnostics
- `05-live-stub-host.log` — copy of the implementer's stub host log
- `06-sc1-s9-detail-offline.png` — offline notice on the source before the move
- `07-sc1-s12-after-move.png` — same conversation on Eugenes-MacBook-Pro after the move
- `08-live-stub-host-source.ts` — the stub server used in the live run
- `09-live-tmux-before-after-final.txt` — `tmux ls` snapshots (new pane `lfg-ac573b` appears after the move, gone at the end)
- `10-sc5-ios-build-binary-strings.log` — byte-grep of `LFG.debug.dylib` in the 17:19 FlowDeck product and the 17:07 installed app
- `s9-detail-offline.png`, `s12-after-move.png`, `stub.log`, `stub-host.ts` — placed here by the implementation agent at 17:20 before this audit began; duplicates of 05–08, left untouched

## Commands

```
# Swift
cd /Users/eugenechan/dev/personal/lfg/ios/LFGCore && swift test --filter SessionTransferTests
cd /Users/eugenechan/dev/personal/lfg/ios/LFGCore && swift test

# Bun / TS
cd /Users/eugenechan/dev/personal/lfg && bun test src/commands/serve-resume-force.test.ts src/leases.test.ts src/commands/serve-fork.test.ts
cd /Users/eugenechan/dev/personal/lfg && npx tsc --noEmit -p .

# Code-path checks
git diff -- src/commands/serve.ts ios/LFGCore/Sources/LFGCore/Models.swift ios/LFGCore/Sources/LFGCore/LFGClient.swift
sed -n 375,395p ios/LFG/SessionStore.swift; sed -n 600,620p …; sed -n 1840,1905p …; sed -n 4060,4080p …; sed -n 4275,4425p …
git show HEAD:ios/LFG/SessionStore.swift | awk '/func transfer\(_ id: String, to target: Host\)/{f=1} f{print NR": "$0; if (++n>70) exit}'
grep -n -A8 'var showsOfflineBanner' ios/LFGCore/Sources/LFGCore/HostState.swift

# Running-server age vs source (SC6 blocker)
ps -eo pid,lstart,command | grep '[c]li.ts serve'          # 41409 @16:05:13 (:8766), 57499 @17:14:05 (:9982, ios-terminal worktree)
stat -f '%Sm %N' src/commands/serve.ts                     # 17:00:14
lsof -nP -iTCP -sTCP:LISTEN -a -p 41409,57499
grep -c foreignLeaseVeto .worktrees/ios-terminal/src/commands/serve.ts   # 0

# iOS build product (SC5)
grep -o -m1 '\-project [^ ]*' ~/.flowdeck/logs/734d3b6e4105/build.log; grep 'BUILD' ~/.flowdeck/logs/734d3b6e4105/build.log
grep -a -o 'lfg.deferredSourceCloses' ~/Library/Developer/FlowDeck/DerivedData/ios-734d3b6e4105/Build/Products/Debug-iphonesimulator/LFG.app/LFG.debug.dylib | wc -l
```

## Notes

- SC6 is the only unverified criterion, and it is unverifiable by design of this audit (no server restart). The unit test `serve-resume-force.test.ts` exercises the same `foreignLeaseVeto` guard the route calls. When the :8766 server is next restarted, the declared curl-with-fixture-lease check is what closes it.
- Out of scope, not affecting the verdict: `close(_:)` calls `deferredSourceCloses.forget(session:)` before the close runs, so a manual "End session" that then fails (for example, the source host still down) also drops the deferred close; the orphan pane would linger when that host returns. Likewise `replayDeferredSourceCloses` `take`s the owed ids before resolving the client, so a host removed from settings loses its owed closes silently. Both are consistent with the "one-shot, best effort" intent in the Decision Log.
- Out of scope: `LFGClient.resume` encodes `force: nil` as JSON `null` on the wire (the `send(json:)` dict maps nil → `NSNull`), so the normal path now sends `"force": null` rather than omitting the key. `testResumeRequestCarriesForceOnlyWhenSet` tests `JSONEncoder` on `ResumeRequest`, not this dict path. The server reads `body?.force === true`, so `null` is correctly not-forced; older servers ignore the key.
- The stub host claims the session as live but writes no lease file, so the live run demonstrates the client's skip/force/defer/replay behaviour, not the server's lease override.
