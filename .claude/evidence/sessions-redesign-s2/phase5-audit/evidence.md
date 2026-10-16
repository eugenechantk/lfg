# Verification Audit

Verdict: PASS (6 of 6 requested checks hold). SC14's "one end-to-end send + answer" leg was outside this audit (no sends allowed); see Notes.
Timestamp: 2026-10-16 16:09 – 16:31 HKT (+0800)
Repository: /Users/eugenechan/dev/personal/lfg (main @ 8aaffc7, = origin/main)
Surface: mixed (api, cli, desktop binary, TestFlight logs)

## Change Audited

Phase 5 ("ship") of the S2 sessions redesign: main at 8aaffc7 (S2 phases 1–4 plus the `src/events-stream.ts` fix for `GET /api/events`, where a resynced stream used to send only heartbeats), running on the Pro and the Air servers; iOS build 202610161522 (v1.3.0) on TestFlight from 7ae892f; desktop app installed at /Applications/lfg.app on both Macs. Criteria: SC1, SC14 and the deploy, as listed by the caller (checks 1–6).

## Success Criteria

| # | Criterion | Declared Method | Command | Observed | Result | Evidence |
|---|---|---|---|---|---|---|
| 1a | Pro server runs code containing 8aaffc7 | process start vs commit time; shasum of events-stream.ts | `ps -o pid=,lstart= -p $(lsof -nP -iTCP:8766 -sTCP:LISTEN -t)`; `shasum src/events-stream.ts`; `git show 8aaffc7:src/events-stream.ts \| shasum` | PID 94865 started 15:53:49; commit 15:53:25; file mtime 15:53:30; HEAD = origin/main = 8aaffc7; `src/` clean; sha1 `839249bb94b6…` for both working tree and commit blob | PASS | `01-pro-server-process.txt` |
| 1b | Air server runs code containing 8aaffc7 | same, over `ssh air` | same, plus `git merge-base --is-ancestor 8aaffc7 HEAD` | PID 90094 started 16:00:23; file mtime 16:00:20; HEAD = 8aaffc7; `src/` clean vs 8aaffc7; sha1 `839249bb94b6…` (same as Pro) | PASS | `02-air-server-process.txt` |
| 2a | SC1: `/api/sessions` rows carry `lastUserAt`; task sessions carry `task` | curl the live Pro | `curl -sS -D - http://127.0.0.1:8766/api/sessions` + jq | 200; 26 rows, all 26 have the `lastUserAt` key (23 numeric, 3 null: no user turn recorded); 8 rows carry `task {id,name}`; all 8 match `~/.lfg/scheduled-tasks.json` runs (sessionId → taskId/taskName); no live row that appears in runs[] lacks `task` | PASS | `03-sc1-sessions.txt`, `03-sc1-sessions.json` |
| 2b | SC1: `/api/sessions/resumable?limit=5` has numeric `total` on page 1 | curl the live Pro | `curl -sS -D - "http://127.0.0.1:8766/api/sessions/resumable?limit=5"` (×2) | 200; `total: 3990` (number), 5 rows, `nextBefore` set; second call `total: 3991` (one more session closed between calls) | PASS | `04-sc1-resumable.txt`, `04-sc1-resumable-call{1,2}.json` |
| 3a | Stream fix on the Pro (discriminating) | resync probe + control, head must move | `10-stream-probe.sh 600`: `curl -sN -m 600 ".../api/events?since=999999999"` and in parallel `since=<head>` | resync stream: 1 `event: resync {"head":1197993}`, then 11 `id:` rows 1197994–1198004 (contiguous, starts at head+1, identical to control); hb moved 1197993 → 1198004. Control: no resync, same 11 ids | PASS | `10-stream-pro-probe3/`, `10-stream-summary.txt` |
| 3b | Stream fix on the Air (discriminating) | same | `10-stream-probe.sh 900` run on the Air | resync stream: 1 `event: resync {"head":77541}`, then 5 `id:` rows 77542–77546 (contiguous, head+1, identical to control); hb moved 77541 → 77546. Control: no resync, same 5 ids | PASS | `10-stream-air-probe2/`, `10-stream-summary.txt` |
| 4 | TestFlight: 202610161522 VALID on 1.3.0, internal IN_BETA_TESTING; IPA CFBundleVersion 202610161522 | verify log + IPA plist | grep the ANSI-stripped `verify-202610161522.log` / `deploy-202610161522.log`; `unzip` + `PlistBuddy` on `ios/build/fastlane/LFG.ipa` | log: `[2/20] build 202610161522: VALID`, `DoD PASS: 202610161522 VALID on train 1.3.0 (highest), internal=IN_BETA_TESTING`; deploy log: uploaded 15:25:55. IPA: CFBundleVersion 202610161522, short 1.3.0, id com.eugenechan.lfg. `git diff 7ae892f 8aaffc7 -- ios/ desktop/` is empty | PASS | `05-testflight.txt` |
| 5a | Desktop app on the Pro | codesign, running process, S2 code in binary | `codesign --verify --deep --strict`; `pgrep -f`; `lsof -d txt`; `strings -a … \| grep -c` vs the pre-S2 backup | codesign exit 0, Developer ID 39GJBP8V5A; PID 19670 since 15:18:54 maps `/Applications/lfg.app/Contents/MacOS/lfg`; `S2DeskRow`, `S2DeskHostStrip`, `S2DeskGroupHeader`, `by last activity` each 1 in installed, 0 in the backup | PASS | `06-desktop-pro.txt` |
| 5b | Desktop app on the Air | same, over ssh | same | codesign exit 0, same signer; PID 62129 since 15:20:12 maps the installed binary; same S2 markers 1 vs 0; binary sha1 `8ac38239…` identical to the Pro's | PASS | `07-desktop-air.txt` |
| 6a | `bun test` green at 8aaffc7 in a clean copy | clean detached worktree | `git worktree add --detach /private/tmp/lfg-audit-8aaffc7 8aaffc7`; symlink node_modules; `~/.bun/bin/bun test --timeout 60000` | 1240 pass, 0 fail, 121 files, exit 0 (bun 1.3.14). Targeted `events-stream.test.ts` + `task-origin.test.ts`: 11 pass | PASS | `08-clean-worktree-setup.txt`, `09-bun-test.log`, `09b-bun-test-targeted.log` |
| 6b | LFGCore `swift test` green at 8aaffc7 | same worktree | `cd ios/LFGCore && swift test` | XCTest: 644 executed, 1 skipped, 0 failures. Swift Testing: 415 tests in 62 suites passed. exit 0. The worktree was removed afterwards; `git status` there showed only the node_modules symlink | PASS | `11-swift-test-lfgcore.log`, `08-clean-worktree-setup.txt` |

SC1 overall: PASS (2a + 2b). SC14 overall: the suites leg PASSES (6a + 6b); the live send + answer leg was not exercised by this audit.

## Artifacts

All under `/Users/eugenechan/dev/personal/lfg/.claude/worktrees/sessions-redesign-s2/.claude/evidence/sessions-redesign-s2/phase5-audit/`:

- `01-pro-server-process.txt`, `02-air-server-process.txt` — check 1
- `03-sc1-sessions.{txt,json}`, `04-sc1-resumable*.{txt,json}` — check 2
- `10-stream-probe.sh` (the probe), `10-stream-pro-probe{1,2,3}/`, `10-stream-air-probe{1,2}/` (raw SSE bodies + `meta.txt`), `10-stream-summary.txt` — check 3
- `05-testflight.txt` — check 4
- `06-desktop-pro.txt`, `07-desktop-air.txt` — check 5
- `08-clean-worktree-setup.txt`, `09-bun-test.log`, `09b-bun-test-targeted.log`, `11-swift-test-lfgcore.log` — check 6
- `12-end-process-check.txt` — both servers still on the same PIDs at the end (no restart during the audit)
- `13-sc14-e2e-indirect.txt` — read-only look at the implementer's own e2e session (Notes)

## Commands

Setup: none. Both servers were already running; nothing was restarted, built or installed.

```sh
# 1
lsof -nP -iTCP:8766 -sTCP:LISTEN -t; ps -o pid=,lstart=,command= -p <pid>
shasum src/events-stream.ts; git show 8aaffc7:src/events-stream.ts | shasum
ssh air 'export PATH=/opt/homebrew/bin:...; export DEVELOPER_DIR=/Library/Developer/CommandLineTools; cd ~/dev/personal/lfg; git log -1; git merge-base --is-ancestor 8aaffc7 HEAD; shasum src/events-stream.ts'
# 2
curl -sS -D - http://127.0.0.1:8766/api/sessions
curl -sS -D - "http://127.0.0.1:8766/api/sessions/resumable?limit=5"
# 3 (Pro locally; Air via scp + nohup on the Air)
10-stream-probe.sh <secs> <outdir>   # curl -sN -m <secs> ".../api/events?since=999999999" ‖ ".../api/events?since=<head>"
# 4
sed 's/\x1b\[[0-9;]*m//g' ios/fastlane/verify-202610161522.log | grep -E 'ground truth|VALID|DoD'
unzip -q ios/build/fastlane/LFG.ipa 'Payload/*.app/Info.plist'; PlistBuddy -c 'Print :CFBundleVersion' …
# 5 (both Macs)
codesign --verify --deep --strict --verbose=2 /Applications/lfg.app
pgrep -f '^/Applications/lfg.app/Contents/MacOS/lfg'; lsof -p <pid> -a -d txt -Fn
strings -a /Applications/lfg.app/Contents/MacOS/lfg | grep -c -F S2DeskRow   # and vs the backup bundle
# 6
git worktree add --detach /private/tmp/lfg-audit-8aaffc7 8aaffc7
ln -s /Users/eugenechan/dev/personal/lfg/node_modules /private/tmp/lfg-audit-8aaffc7/node_modules
(cd /private/tmp/lfg-audit-8aaffc7 && ~/.bun/bin/bun test --timeout 60000)
(cd /private/tmp/lfg-audit-8aaffc7/ios/LFGCore && swift test)
rm /private/tmp/lfg-audit-8aaffc7/node_modules; git worktree remove /private/tmp/lfg-audit-8aaffc7
```

## Notes

- **Discrimination, check 3.** The first probes did not meet the "head moved" rule. On the Pro 40 s run, two `id:` rows arrived after the last heartbeat, so the `hb` lines did not move. The Pro 90 s run and the Air 40 s run saw no events. The 600 s (Pro) and 900 s (Air) runs met the rule. No sessions were created. The events came from other agents' normal work. The old code would show `resync` followed by heartbeats and zero `id:` rows, while the control in the same window showed rows. Here the resync stream's ids match the control's one for one.
- **SC14 live leg (not audited).** The caller forbade sends, so this audit did not run "one end-to-end send + answer on a real session". The only evidence is indirect and read-only: transcript `3ae67248…` (cwd `~/inbox/s2-e2e-check`). It shows an AskUserQuestion answered at 16:06:42 and a sent message ("Reply with the single word fourth") answered at 16:07:23. Both happened after the Pro restart at 15:53:49. `~/.lfg/sendq.log` shows enqueue → deliver-queued → reconcile-delivered with 1 attempt. This audit did not drive any of it (`13-sc14-e2e-indirect.txt`).
- **Desktop marker.** The caller's example string "by last activity" is a literal in `desktop/LFGSessions.swift:6311` (added with S2), not in `SessionsListS2.swift`. The first note in `06-desktop-pro.txt` calling it interpolated is wrong; the appended lines correct it. In `07-desktop-air.txt`, the `n/a` lines are a shell artifact (`grep -c` printed 0, then exited 1). The backup binary exists, and its count is 0.
- **Out of scope.** `GET /api/sessions/resumable?limit=5` took 21.2 s and 17.8 s on the Pro. `/api/ping` stayed at ≤ 49 ms during the second call, so the event loop was not blocked. A phone or desktop waiting on page 1 will see this delay.
- **Out of scope.** 3 of 26 live rows have `lastUserAt: null`. Two are scheduled-task codex sessions that do carry `task`. They have no recorded user turn, and the key is still present.
- **Out of scope.** The Air server runs `/opt/homebrew/bin/bun`, which is 1.3.14, the same version as the Pro's `~/.bun/bin/bun`. The older Homebrew Bun 1.2.15 crash noted in memory does not apply.
- Probe temp files on the Air (`/tmp/lfg-audit-*`) were removed. The temporary worktree was removed.
