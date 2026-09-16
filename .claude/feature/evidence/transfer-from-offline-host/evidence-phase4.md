# Verification Audit — Phase 4 (Pre-flight on the target)

Verdict: PASS
Timestamp: 2026-09-15 17:53 HKT (09:53 UTC)
Repository: /Users/eugenechan/dev/personal/lfg
Surface: mixed (Bun server unit tests, LFGCore Swift package tests, iOS build product, review of the implementer's recorded live seam via a stub target host)

Scope: SC7, SC8, SC9 of `.claude/feature/transfer-from-offline-host.md`. SC1–SC6 were audited earlier (`evidence.md`) and are not re-examined here.

PASS means: every criterion in scope was checked and holds; the caller's five code-review checks (a)–(e) all hold; no logic bug was found. The live seam is the implementer's recording (reviewed, not re-run, per instructions) — it is consistent with the code and the unit tests on every point checked.

## Change Audited

Uncommitted working-tree change, phase 4 portion only:

- `src/commands/serve.ts` — `transcriptStatus(sessionId, resolve)` (exported) and route `GET /api/sessions/:id/transcript-status` inserted at line 2118–2121, before `/api/sessions/resumable`. `found:false` is a 200 body. `lastActivityAt` = last message `ts` from `previewLast` (mtime only as a fallback when the last message has no timestamp).
- `src/sessions.ts` — `previewLast` exported (line 2587). No other phase-4 change in this file (the rest of its diff is unrelated concurrent work).
- `ios/LFGCore/Sources/LFGCore/Models.swift:472` — `TranscriptStatus` (lenient decoder, `found` defaults false).
- `ios/LFGCore/Sources/LFGCore/LFGClient.swift:554` — `transcriptStatus(_:)` → `get("api/sessions/<id>/transcript-status")`; `performRaw` throws `LFGError.http(status:)` for any non-2xx (line 268–270).
- `ios/LFGCore/Sources/LFGCore/SessionTransfer.swift:57–106` — `Preflight` enum, `staleThreshold = 60`, `preflight(status:sourceLastActivityAt:)`, `behindLabel`.
- `ios/LFG/SessionStore.swift:4319–4329` `transferPreflight`; `4354–4380` the gate at the top of `transfer(_:to:preflight:)`.
- `ios/LFG/SessionDetailView.swift:1307–1341` stale-move state + `confirmationDialog("Move anyway?")`; `1526–1537` `transfer(to:)` runs the pre-flight first.
- Tests: `src/commands/serve-transcript-status.test.ts` (3), `SessionTransferTests` pre-flight cases (7 of 14).

## Success Criteria

| Criterion | Declared Method | Result | Evidence |
|---|---|---|---|
| SC7 — Target asked BEFORE the source is touched; a target without the transcript refuses with "<target> doesn't have this transcript yet"; source pane untouched | `testPreflightMissingTranscriptBlocks` + `serve-transcript-status.test.ts` + live seam (stub target, `TS_MODE=missing`) | PASS | `p4-02-swift-test-SessionTransferTests.log` — `testPreflightMissingTranscriptBlocks` passed (`.missing`, `blocks == true`). `p4-03-bun-test.log` — `serve-transcript-status.test.ts` "missing transcript → found:false (a body, not a throw)" passed (26 pass / 0 fail across the three files). Code: `SessionStore.swift:4364` runs the pre-flight before line 4381 (`plan`) and 4385 (`sourceClient.close`); `4366–4368` `.missing` sets `lastError = "Transfer: <target> doesn't have this transcript yet — …"` and returns nil. Live (implementer's recording, reviewed): `stub.log` line 108 `GET /api/sessions/50980bea…/transcript-status` at 09:48:35.836Z with the stub in `TS_MODE=missing` (restart at line 36, 09:41:30Z); `sc7-missing-transcript-banner.jpg` (17:49:12 HKT) shows the banner with exactly that copy on the session still titled `Eugenes-MacBook-Pro`; `sc7-missing-transcript-tree.json` has three `sessionErrorBanner` nodes with the same label. `p4-05-stub-log-analysis.txt`: zero `close`/`CLOSE` lines after line 33 (09:18:58Z, the SC4 deferred close from the earlier phase) — the only POSTs after that are `/api/push/register`. |
| SC8 — A copy >60s behind gets a confirmation dialog ("… is N behind …") instead of a silent fork; Cancel leaves the source untouched | `testPreflightStaleCopyAsksInsteadOfBlocking` + live seam (`TS_MODE=stale`, dialog screenshot, Cancel, source pane still live) | PASS | `p4-02-…log` — `testPreflightStaleCopyAsksInsteadOfBlocking` passed (`.behind(seconds ≈ 840)`, `blocks == false`, `needsConfirmation == true`); `testPreflightFreshCopyIsReady` (20s behind → `.ready`) and `testBehindLabel` passed. Code: `SessionTransfer.swift:91–93` `(src - tgt)/1000 > 60` → `.behind`; `SessionDetailView.swift:1532–1535` `.behind` sets `staleMove` and returns WITHOUT calling `store.transfer`; the dialog's only non-cancel button (1330–1336) calls `store.transfer(sid, to:, preflight: .ready)`; `Cancel` (1337) is a no-op; `SessionStore.swift:4374–4377` a `.behind` that reaches the store returns nil with "Confirm the move to continue." Live: `stub.log` line 114 stub restart 09:49:12Z (stale mode), line 119 pre-flight hit 09:49:36.236Z; `sc8-stale-copy-dialog.png` (17:50:03 HKT) shows "Move anyway? stub-offline-test's copy of this conversation is 22 days behind Eugenes-MacBook-Pro. Moving now continues from that older copy; the newer turns stay only on Eugenes-MacBook-Pro." with a single "Move to stub-offline-test" button. No close request follows in the log (`p4-05-stub-log-analysis.txt`). |
| SC9 — HTTP 404 (old server) → `.unknown`, move proceeds exactly as before; missing cwd refused naming the path; full `swift test` green | `transferPreflight` 404 branch by inspection + `testPreflightMissingCwdBlocksWithPath`; full `swift test` green | PASS | `p4-01-swift-test-full.log` — 524 tests, 1 skipped, 0 failures (XCTest) + 144 Swift Testing tests passed; exit 0. `p4-02-…log` — `testPreflightMissingCwdBlocksWithPath` → `.cwdMissing("/Users/x/repo")`; `testTranscriptStatusDecodesLenientlyAndFoundDefaultsFalse` passed. 404 branch (inspection, as declared): `LFGClient.swift:268–270` throws `LFGError.http(status: 404, …)` for any non-2xx; `SessionStore.swift:4324–4325` `catch LFGError.http(let status, _) where status == 404 { return .unknown }`; `4378–4379` `.unknown, .ready: break` — the pre-existing plan/close/resume code from line 4381 onward is unchanged (compare the earlier audit's SC5 row). Missing cwd copy: `4369–4371` "Transfer: <target> has no <cwd> — this session's directory only exists on <source>." Server side, `serve-transcript-status.test.ts` "a cwd that only exists on the other Mac → cwdExists:false" passed. Incidental live confirmation of the 404 case: the long-lived :8766 server (pid 93726, started 17:28:23, predates the 17:37:59 `serve.ts` edit) answers `GET /api/sessions/<uuid>/transcript-status` with `HTTP 404 {"error":"not found"}` — exactly the shape the client maps to `.unknown` (read-only probe; not re-run through the app). |

## Code review against the caller's checklist (a)–(e)

- (a) Pre-flight runs BEFORE any close on the source, on both paths — HOLDS. Store path: `SessionStore.swift:4363–4364` computes `check` (calling `transferPreflight` when none is passed) and the `switch` at 4365 returns on every blocking case before `plan` (4381) and `sourceClient.close(id)` (4385). `transferPreflight` (4319–4329) only calls `client.transcriptStatus` on the TARGET's client; it never touches `sourceClient`. View path: `SessionDetailView.swift:1531` `store.transferPreflight` first, then either parks a `.behind` (1532–1535) or forwards `check` into `store.transfer(preflight:)` (1536), where the same switch runs before the close.
- (b) 404 → `.unknown` and proceed unchanged; `found:false` → `.missing` and refuse — HOLDS. `LFGClient.performRaw` maps every non-2xx to `.http(status:)` (268–270), `transferPreflight` catches exactly `status == 404` as `.unknown` (4324–4325); other statuses and transport errors become `.targetUnreachable` (4326–4328), which refuses (4372–4373) — reasonable, since a target that can't answer can't resume either. `SessionTransfer.preflight` line 89 `guard status.found else { return .missing }`; `TranscriptStatus.init(from:)` defaults `found` to false on a missing/garbage key, so an old server that somehow 200'd a non-JSON body would refuse rather than proceed (covered by `testTranscriptStatusDecodesLenientlyAndFoundDefaultsFalse`). Server: `transcriptStatus` returns `{found:false}` as a 200 body for an unresolvable id (route line 2120 → `json(...)`), and `resolveTranscript` (sessions.ts:3169–3172) returns null for any non-UUID id, so the `[^/]+` capture cannot reach the filesystem with an arbitrary string.
- (c) `.behind` never moves silently — HOLDS. View: `.behind` sets `staleMove` and returns (1532–1535); the dialog's confirm button is the only call with `preflight: .ready` (1334); Cancel (1337) does nothing. Store: `.behind` without confirmation → `lastError` + `return nil` (4374–4377). `Preflight.blocks` is false for `.behind` and `needsConfirmation` true (SessionTransfer.swift:72–81), matching the Decision Log ("stale is a confirmation, not a refusal").
- (d) Staleness uses the target's last MESSAGE timestamp vs `Session.lastActivityAt`, threshold 60s — HOLDS. Server: `serve.ts` `transcriptStatus` sets `lastActivityAt: last?.ts ?? mtimeMs` where `last = await previewLast(path)` (the last normalised message; `ts` is `Date.parse(x.timestamp)` in ms); the unit test asserts `lastActivityAt === Date.parse("2026-09-15T08:00:00.000Z")` for a file whose mtime is "now". Client: `SessionTransfer.preflight` compares `sourceLastActivityAt` (from `session(id)?.lastActivityAt`, `Session.lastActivityAt: Double?` in epoch ms, Models.swift:22) with `status.lastActivityAt` (ms), divides by 1000, and uses `staleThreshold: TimeInterval = 60` (lines 86–93). Both sides are ms → seconds; `testPreflightStaleCopyAsksInsteadOfBlocking` asserts 14 min → 840 s ± 1. mtime is only used server-side as a fallback when the last message carries no timestamp, and `mtimeMs` is a separate field the client never compares against. `testPreflightWithoutTimestampsIsReadyNotStale` covers either side being nil → `.ready`.
- (e) Route regex cannot shadow other `/api/sessions/...` routes — HOLDS. `/^\/api\/sessions\/([^/]+)\/transcript-status$/` is anchored and requires the literal `/transcript-status` suffix, so it can only ever match its own path; `/api/sessions/resumable`, `/resume`, `/fork`, `/new` and every `/:uuid/<verb>` route have different suffixes. Ordering: every matcher before it in the handler (lines 1714–2098) is an exact `path === "..."` or the `/:uuid/user$/` regex — none of them can consume a `…/transcript-status` path, so the new route is reachable. Placed at 2118–2121, after `/api/sessions` (1954) and `/user` (2098), before `/resumable` (2123). Additionally the route is gated on `req.method === "GET"`. A malformed percent-encoding in the id would make `decodeURIComponent` throw, which Bun's `error(e)` handler (serve.ts:1195) turns into a 500 rather than a crash — not a criterion, noted for completeness.

No logic bug found in the audited paths.

## Live-seam log reconciliation (caller's item 4)

`stub.log` (UTC; local = UTC+8), from `p4-05-stub-log-analysis.txt`:

| Claim | In the log? | Note |
|---|---|---|
| Stub relaunched as TARGET in `TS_MODE=missing` | line 36, `stub up` 09:41:30Z | line 37 (`/abc/transcript-status`, 09:41:31Z) and line 115 (`/x/…`, 09:49:13Z) are curl smoke-tests of the stub itself — a non-UUID id, one second after each restart, not app traffic. |
| SC7 pre-flight hit 09:48:35Z, no close | line 108, 09:48:35.836Z; zero close lines after line 33 | Three earlier hits in the same missing-mode run (lines 81, 93, 99 at 09:45:16Z, 09:46:32Z, 09:47:28Z) are additional attempts at the same move — each also followed by no close, so they only strengthen SC7. The screenshot (17:49:12 HKT) postdates the 09:48:35Z hit. |
| Stub relaunched in `TS_MODE=stale` | line 114, `stub up` 09:49:12Z | |
| SC8 pre-flight hit 09:49:36Z, dialog shown, Cancel, no close | line 119, 09:49:36.236Z; dialog in `sc8-stale-copy-dialog.png` (17:50:03 HKT); no close lines after | The stub in stale mode reports `lastActivityAt` = `STALE_MS` ago; the dialog's "22 days behind" is consistent with the doc's stated 30-day-old copy vs an 8-day-old source. The Cancel tap itself is not observable in the log (a no-op by design); "no close request" is what the criterion demands and it holds. |
| Source pane still in `tmux ls` | not in the stub log | The source in this run was a real Pro pane (`lfg-72f509`), not the stub, so the stub log cannot show it. The doc states the pane survived and was closed manually in cleanup; the absence of any `POST …/close` to the stub plus the banner/dialog appearing on a session still homed on `Eugenes-MacBook-Pro` (both screenshots show that host label) supports it. Not independently re-verified (do-not-re-run constraint). |

Build freshness (`p4-06-build-freshness.txt`): the FlowDeck build that produced the installed app succeeded at 17:41:55, after the last phase-4 source edit (17:40:31), and its `LFG.debug.dylib` (17:41:56) contains "doesn't have this transcript yet", "Move anyway?", "Confirm the move to continue", "transcript-status", "can't reach ", and "under a minute". The live seam (17:48–17:50) therefore exercised the final code.

## Artifacts

All under `/Users/eugenechan/dev/personal/lfg/.claude/feature/evidence/transfer-from-offline-host/`:

- `p4-01-swift-test-full.log` — `swift test`: 524 XCTest tests (1 skipped, 0 failures) + 144 Swift Testing tests passed; task runner exit 0
- `p4-02-swift-test-SessionTransferTests.log` — `swift test --filter SessionTransferTests`: 14 tests, 0 failures, exit 0
- `p4-03-bun-test.log` — `bun test` over the three named files: 26 pass / 0 fail, exit 0 (the forced-override log line is printed by `serve-resume-force.test.ts`)
- `p4-04-tsc-noEmit.log` — `npx tsc --noEmit -p .`: no diagnostics, exit 0
- `p4-05-stub-log-analysis.txt` — grep-derived index of `stub.log`: all pre-flight hits, all close lines, all restarts, all POSTs after 09:18:58Z, artefact mtimes
- `p4-06-build-freshness.txt` — build-log timestamp vs source mtimes; byte-grep of `LFG.debug.dylib` for the phase-4 strings
- Reviewed, not created: `sc7-missing-transcript-banner.jpg`, `sc7-missing-transcript-tree.json`, `sc8-stale-copy-dialog.png`, `stub.log`, `stub-host.ts` (implementer's recording)

## Commands

```
# Swift
cd /Users/eugenechan/dev/personal/lfg/ios/LFGCore && swift test
cd /Users/eugenechan/dev/personal/lfg/ios/LFGCore && swift test --filter SessionTransferTests

# Bun / TypeScript (repo root)
bun test src/commands/serve-transcript-status.test.ts src/commands/serve-resume-force.test.ts src/leases.test.ts
npx tsc --noEmit -p .

# Diff / code read
git diff -- src/commands/serve.ts src/sessions.ts ios/LFG/SessionStore.swift ios/LFG/SessionDetailView.swift \
  ios/LFGCore/Sources/LFGCore/Models.swift ios/LFGCore/Sources/LFGCore/LFGClient.swift
sed -n 4300,4460p ios/LFG/SessionStore.swift
sed -n 1295,1350p ios/LFG/SessionDetailView.swift; sed -n 1495,1545p ios/LFG/SessionDetailView.swift
sed -n 233,280p ios/LFGCore/Sources/LFGCore/LFGClient.swift
awk 'NR>=1700 && NR<2119 && /path\.match\(|path === "|path\.startsWith\(/ {print NR": "$0}' src/commands/serve.ts

# Live evidence review
grep -n "transcript-status\|close\|CLOSE\|stub up" .claude/feature/evidence/transfer-from-offline-host/stub.log
awk 'NR>33 && /POST/' .claude/feature/evidence/transfer-from-offline-host/stub.log
grep -n "BUILD SUCCEEDED" ~/.flowdeck/logs/734d3b6e4105/build.log
strings …/ios-734d3b6e4105/Build/Products/Debug-iphonesimulator/LFG.app/LFG.debug.dylib | grep -c "doesn't have this transcript yet"

# Read-only probe of the long-lived server (deploy-gap note only)
curl -s -w "\nHTTP %{http_code}\n" http://127.0.0.1:8766/api/sessions/00000000-0000-4000-8000-000000000000/transcript-status
```

## Notes

- Deploy gap, not a defect: the running `lfg serve` on :8766 (pid 93726, started 17:28:23) predates the 17:37:59 `serve.ts` edit and returns 404 for the new route. Until it (and the Air's server) is restarted, every real-host move takes the SC9 `.unknown` path — i.e. behaves exactly as before phase 4. The stub-based live seam is the only place the `found:false` / stale branches have run end-to-end so far.
- The live seam's "source pane still in `tmux ls`" claim is supported indirectly (no close reached the stub; both screenshots still show the session on the Pro) but was not re-verified against tmux, per the do-not-re-run instruction.
- Two `stub.log` lines (`/abc/…` at 09:41:31Z and `/x/…` at 09:49:13Z) are curl smoke-tests of the stub, not app traffic; they do not affect either criterion.
- Out of scope, observed: a `TranscriptStatus` with `cwd: null` (server could not read a cwd from the transcript head) skips the cwd check on the client and is `.ready`; the server's resume falls back to `SELF_REPO` in that case. Consistent with "refuse naming the path" only being possible when there is a path.
- Out of scope, observed: `transferPreflight` maps every non-404 HTTP status (e.g. 500) to `.targetUnreachable`, which refuses. Sensible, but a 5xx from a *new* server on a transient fault will read as "can't reach <target>" rather than a server error.
