# Verification Audit

Verdict: PASS
Timestamp: 2026-09-06 18:41 (local, Eugenes-MacBook-Pro)
Repository: /Users/eugenechan/dev/personal/lfg
Surface: mixed (cli harness + api + unit tests)

## Change Audited
codex-resume-fails-loudly (`.claude/feature/codex-resume-fails-loudly.md`): `codexBin()` newest-version resolution; `awaitCodexBootstrap` remain-on-exit watch (settle = composer + `model · cwd` status line held 1s, or death, cap 30s); `resumeClosedSession` codex branch tears down + 502 on death; iOS `pendingResumes` expiry.
Deployed server: pid 85787 started 18:37:37, newer than `src/tmux.ts` (18:37:05) and `src/commands/serve.ts` (18:35:39) — running the final code. Not restarted, `.env` untouched.

## Success Criteria
| # | Criterion | Declared Method | Result | Evidence |
|---|---|---|---|---|
| 1 | bun unit tests (codex-bin, tmux-argv, tmux-pane-size) | `bun test …` | PASS — 25 pass, 0 fail, 3 files | `01-bun-tests.log` |
| 2 | Swift `ResumeSettlementTests` | `swift test --filter ResumeSettlementTests` | PASS — 5 tests, 0 failures | `02-swift-tests.log` |
| 3 | Offline failure path (SC2): codex 0.146.0 pinned vs fork thread `01a07644…` | harness `harn.ts lfg-audit01` | PASS — pane dead at 1.6s (status 1), `failure` non-null and contains `unknown variant \`completed\``; `tmux ls` has no `lfg-audit01` | `03-sc2-harness-failure.log`, `03b-sc2-harness-failure-fulltext.log` (full string; grep count 1) |
| 4 | Offline success path (SC3): current codex 0.153.4 vs scratch thread, no prompt | harness `harn.ts lfg-audit02 … ""` | PASS — `failure: null`, `settled=true` at t=3524ms (status line at 2444ms + 1s dwell; run overlapped the 0.146 harness); `tmux ls` has no `lfg-audit02` | `04-sc3-harness-success.log` |
| 5 | Deployed server resume + list + remain-on-exit + close | curl against 127.0.0.1:8766 | PASS — `POST /api/sessions/resume` → HTTP 200 in 2.3s, `ok:true`, `tmuxName lfg-f054fa`; `/api/sessions` row: `tmuxTarget "lfg-f054fa:0.0"`, pid 90739, agent codex; `tmux show -w -t '=lfg-f054fa:0' remain-on-exit` → `off`; pane alive (pane_dead 0) with composer + `gpt-6-astra high fast · …` status line; `/close` → `{"ok":true,"panes":1}`, `has-session` → can't find; global remain-on-exit still `off` | `05-sc3-resume-http.txt`, `05-sc3-resume-response.json`, `06-sc3-api-sessions-row.json`, `07-sc3-remain-on-exit-and-pane.txt`, `08-sc3-close.txt` |
| 6 | Code read of `awaitCodexBootstrap`, `codexPaneSettled`, `codexErrorFromPane`, `codexBin`, `resumeClosedSession` | read + probes | Reviewed; concerns below (none block the stated criteria) | `09-code-probes.log` |

## Artifacts
- `01-bun-tests.log` — bun test output
- `02-swift-tests.log` — swift test output
- `03-sc2-harness-failure.log` — implementer harness (160-char truncation), 0.146 pinned
- `03b-sc2-harness-failure-fulltext.log` — same run via an audit copy printing the full failure string + tmux ls
- `04-sc3-harness-success.log` — success harness ticks + tmux ls
- `05-sc3-resume-http.txt`, `05-sc3-resume-response.json` — deployed resume
- `06-sc3-api-sessions-full.json`, `06-sc3-api-sessions-row.json` — listing
- `07-sc3-remain-on-exit-and-pane.txt` — window option + pane_dead + capture
- `08-sc3-close.txt` — close response, tmux ls, has-session, global remain-on-exit
- `09-code-probes.log` — codexBin cache / codexPaneSettled / codexErrorFromPane probes

## Commands
```
bun test src/codex-bin.test.ts src/tmux-argv.test.ts src/tmux-pane-size.test.ts
cd ios/LFGCore && swift test --filter ResumeSettlementTests
S=<scratchpad>; LFG_CODEX_BIN=$S/codex146/node_modules/.bin/codex bun $S/harn.ts lfg-audit01 01a07644-573e-72a3-8212-aa1865861042 "Reply with the single word ok"
LFG_CODEX_BIN=$S/codex146/node_modules/.bin/codex bun $S/harn-audit-full.ts lfg-audit01 01a07644-… "Reply with the single word ok"   # harn.ts with the slice(0,160) removed
bun $S/harn.ts lfg-audit02 01a0762b-fd62-7cc2-a690-ec5839c93789 ""
curl -s -X POST localhost:8766/api/sessions/resume -H 'content-type: application/json' -d '{"sessionId":"01a0762b-fd62-7cc2-a690-ec5839c93789"}'
curl -s localhost:8766/api/sessions | jq '.sessions[] | select(.sessionId=="01a0762b-…")'
tmux show -w -t '=lfg-f054fa:0' remain-on-exit; tmux capture-pane -p -t lfg-f054fa:0.0
curl -s -X POST localhost:8766/api/sessions/01a0762b-fd62-7cc2-a690-ec5839c93789/close; tmux has-session -t '=lfg-f054fa'
```

## Notes
Limitations
- The server-side failure branch (kill + removeManaged + 502, serve.ts:217-230) was NOT exercised against the deployed server in this audit: `LFG_CODEX_BIN` is read from the running process env and the rules forbid restarting/editing `.env`. Only the offline harness (criterion 3) and the implementer's earlier live 502 evidence (`../sc2-*.txt`) cover it. The sendq "not delivered" clause of SC2 was likewise not re-verified here.
- SC4 (update-prompt dismissal) not reproducible live (0.153.4 is latest); only `dismissCodexUpdatePrompt` being called per poll (tmux.ts:484) is observable in code. Unverified live, as the doc records.
- Criterion 4's settle came at 3.5s not ~3s; the run overlapped the 0.146 harness and the status line itself landed at 2.4s. Harmless.

Concerns (demonstrated, none fail a stated criterion)
1. `codexBin()` caches for the process lifetime (`09-code-probes.log`: second call ignores a changed env). The server is long-lived by policy, so a codex upgrade after boot (the exact skew that caused the incident, e.g. codex self-updating `~/.bun/bin`) is never re-resolved — SC1's "never resumes with an older codex than the thread's writer" holds only per server start. The failure is now loud (502) instead of silent, but the fix does not survive the next upgrade without a restart. Suggest re-resolving on each resume (or on failure).
2. `awaitCodexBootstrap` returns `null` (= success) at the 30s cap; `resumeClosedSession` then switches remain-on-exit off and reports ok. A pane that dies after 30s reproduces the original silent-vanish. Documented trade-off in the code comment; not observed in this audit.
3. In the prompt-on-argv failure case the `Error:` head is lost to the alternate screen and the returned text starts mid-path (`73e-72a3-…jsonl: thread/resume failed …`, `03b-*`). Still contains the actionable clause; cosmetic.
4. `resumeClosedSession` failure path calls `tmuxKillSession` before `removeManaged` — a concurrent `listSessions` between the two sees a managed row with no pane. Transient, not demonstrated.

Out of scope observations: none.
Cleanup: only `lfg-audit01`, `lfg-audit02`, `lfg-f054fa` were created; all gone. User sessions lfg-9f9e10/f59c9d/4bf7f5/37d7c4/514c45 untouched. Global remain-on-exit `off`.
