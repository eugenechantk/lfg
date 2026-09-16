# Feature: codex-resume-fails-loudly

## User Story
As Eugene sending a message to a closed codex session from the phone, I want the resume to either come up live or fail with codex's actual error, so a message never shows "delivered" into a pane that died, and the session never vanishes from my list.

## User Flow
1. Open a closed codex session on iOS, type a message, send.
2. Server resumes the thread in a new managed tmux pane with the message as the kickoff prompt.
3a. Codex comes up → row goes live, message lands, turn runs.
3b. Codex exits during bootstrap → send fails with codex's stderr line (e.g. `failed to deserialize stored thread item …`), the pane and managed row are torn down, the closed row stays in the list so the user can retry after fixing the cause.
4. If a resumed codex session is later ended, it returns to the Closed list (it used to disappear until app relaunch).

## Success Criteria
- [x] SC1: `codexBin()` picks the newest installed codex among PATH and the known install dirs (`~/.bun/bin`, `~/.local/bin`, `/usr/local/bin`, `/opt/homebrew/bin`), so lfg never resumes with an older codex than the one that wrote the thread — **Verify by:** unit tests for `pickNewestCodex`/`parseCodexVersion`; runtime probe `bun -e` printing the chosen path + version on this host.
- [x] SC2: A codex resume whose pane dies during bootstrap returns HTTP 502 whose `error` contains codex's `Error:` line, kills the tmux session and removes the managed row; the sendq row is NOT recorded as delivered — **Verify by:** unit test for `codexPaneFailure()` on the captured pane text; live: `POST /api/sessions/<id>/message` against a thread the old binary can't read (0.146 copy kept aside as the fixture) → 502 with the deserialize error, `tmux ls` shows no `lfg-*` for it, managed-sessions has no row.
- [x] SC3: A healthy codex resume still returns ok, the pane keeps running (remain-on-exit is switched back off so a later normal exit doesn't leave a dead pane), and the message lands — **Verify by:** live `POST /api/sessions/01a07207…/message` with Eugene's original text after the upgrade → `resumed: true`, `/api/sessions` lists the id with a `tmuxTarget`, pane shows the turn running; `tmux show -t <name> remain-on-exit` is off.
- [x] SC4: The resume poll dismisses codex's "Update available" selector like the create/fork paths do — **Verify by:** code path calls `dismissCodexUpdatePrompt` in the loop (unit-level: grep/test), live: not reproducible today (no newer version), recorded as such.
- [x] SC5: iOS: a resumed id-stable (codex) session leaves `resumedIds` once it is seen live, or after 60s if it never goes live, so a failed resume or a later End returns the row to Closed — **Verify by:** LFGCore/app unit test on the pending-resume expiry helper; `swift test` green.

## Platform & Stack
- **Platform:** Bun server (`src/`), iOS client (`ios/`)
- **Language:** TypeScript, Swift

## Steps to Verify
1. `bun test src/codex-bin.test.ts src/tmux-argv.test.ts src/tmux-pane-size.test.ts`
2. `cd ios/LFGCore && swift test --filter Resume` (or the whole package)
3. Restart the server by port (`lsof -nP -iTCP:8766 -sTCP:LISTEN -t | xargs kill`; serve-forever respawns), probe a changed endpoint.
4. Live SC2/SC3 as above; evidence under `.claude/feature/evidence/codex-resume-fails-loudly/`.

## Implementation Phases
### Phase 1: server (tmux.ts, serve.ts)
- Scope: newest-codex resolution; `codexPaneFailure` parser; remain-on-exit watch window in the codex resume path; update-prompt dismissal.
- SC1–SC4. Gate: bun tests + live probes.
### Phase 2: iOS (SessionStore)
- Scope: `pendingResumes` expiry.
- SC5. Gate: swift tests.

## Decision Log
- **Watch window instead of an async watcher.** The resume handler blocks up to `CODEX_RESUME_WATCH_MS` (6s) polling for pane death, exiting early only on death. Alternative: return immediately and retract the sendq row asynchronously — more machinery (journal retraction + client outbox state) for a path that already tolerates a 14s create wait.
- **remain-on-exit toggled, not left on.** Left on, a normally exited codex leaves a dead pane + managed row forever (phantom card). Toggled off once the window passes.
- **Newest version wins over PATH order.** Consistency with Eugene's shell is the real invariant, but "highest version" is what guarantees readability of every thread on the box, and codex's own updater installs to `~/.bun/bin`, off the server's PATH.
- **Claude's `resumedIds` semantics untouched.** For Claude the suppressed id is the stale old transcript (dedupe), not a gap-filler; the expiry only applies to id-stable resumes.

- **One install, the bun one (Eugene, after delivery).** Options were keep Homebrew/npm (on every PATH already) or keep bun (`~/.bun/bin`, where the TUI's "Update now" installs). Eugene chose bun because he will sometimes press "Update now"; paths were made to follow it instead: `npm uninstall -g @openai/codex`, `serve-forever.sh` prepends `$HOME/.bun/bin`, desktop already resolves via a login shell. Verified: a server-spawned pane runs `node ~/.bun/bin/codex`.

## Verification Evidence

Evidence dir: `.claude/feature/evidence/codex-resume-fails-loudly/`. Harness scripts used for the offline runs: `harn.ts` / `harn2.ts` in the session scratchpad (drive `spawnManagedCodexSession` + `awaitCodexBootstrap` against a named tmux session; `LFG_CODEX_BIN` pins the binary).

| SC | Method | Observed | Artifact |
|---|---|---|---|
| SC1 | `bun test src/codex-bin.test.ts` (10 tests: version parse, newest-wins, PATH-order ties, unknown-version) | 10 pass | test output in session; `sc1-codex-using.txt` |
| SC1 | runtime probe, deployed server log at first spawn | `[codex] using /opt/homebrew/bin/codex (0.153.4); other copies: /Users/eugenechan/.bun/bin/codex (0.153.4)` (both 0.153.4 after `npm i -g @openai/codex@0.153.4`; tie keeps PATH order) | `sc1-codex-using.txt` |
| SC2 | live: server pinned to codex 0.146.0 via `.env` `LFG_CODEX_BIN`, `POST /api/sessions/01a07644-573e-72a3-8212-aa1865861042/send` (fork of the failing thread, written by 0.153.4) | `HTTP 502 in 1.38s`, body `codex could not resume this session: … thread/resume failed … unknown variant \`completed\` … (code -32603)`; `tmux ls` has no `lfg-*` for it; managed rows for the fork: `[]`; sendq rows for the clientId: 0; server log `[resume] codex 01a07644… died during bootstrap: …` | `sc2-http.txt`, `sc2-response.json`, `sc2-tmux-ls.txt`, `sc2-managed.txt`, `sc2-serve-log.txt` |
| SC2 | offline harness, pinned 0.146 vs the fork, with and without the exact 17:56 message text, my env and the server's `env -i` env | pane dead at 1.1–3.2s, failure text captured each time | session output (harness A/B/C) |
| SC2 | unit: `codexErrorFromPane` on the verbatim 120-col capture (Error: head present) and on the head-lost variant (alternate screen) | rejoined single line, no tmux trailer | `bun test src/codex-bin.test.ts` |
| SC3 | live, unpinned 0.153.4: `POST /api/sessions/01a07207…/send` with Eugene's original message | `HTTP 200 in 6.2s`, `resumed: true`, `tmuxName lfg-4bf7f5`; `/api/sessions` lists the id with `tmuxTarget lfg-4bf7f5:0.0`, pid 57039; pane shows the turn ran and codex answered ("Yes. Staging and production accounts are separate…"); rollout gained one `task_started`/`task_complete` pair at 10:24:03–13Z; `remain-on-exit off` on the window; sendq row `delivered` | `sc3-http.txt`, `sc3-response.json`, `sc3-pane.txt`, `sc3-api-sessions.json`, `sc3-remain-on-exit.txt`, `sc3-sendq.txt` |
| SC3 | live on the FINAL deployed code (pid 85787): `POST /api/sessions/resume` for the scratch thread, then `/close` | `HTTP 200 in 7.9s`, pane alive with composer + status line, `remain-on-exit off`, `/api/sessions` row has `tmuxTarget`; close → `{"ok":true,"panes":1}`, session gone | `sc3b-*.txt/json` |
| SC3 | offline: 0.153.4 vs scratch thread → settled at 1.6s (composer 250ms, status line 370ms, 1s dwell); 0.153.4 vs a thread with an active writer → failure at 0.5s, never settled | harness B / A | session output |
| SC4 | `awaitCodexBootstrap` calls `dismissCodexUpdatePrompt` every poll (code); live not reproducible today (0.153.4 is latest — no selector) | recorded as unverified-live | — |
| SC5 | `cd ios/LFGCore && swift test --filter ResumeSettlementTests` | 5 tests, 0 failures | session output |
| SC5 | `flowdeck build -p LFG.xcodeproj -s LFG` (SessionStore.swift edits compile) | Build Completed | session output |

Full `bun test`: 740 pass, 1 fail — `sessions-resumable-closed.test.ts` "stale lease IS returned as closed" (pre-existing timing flake; passes alone; untouched area).

## Bugs

- **Fixed:** first live SC2 attempt (pinned 0.146, the real 18MB thread) returned 200 — the pane outlived the fixed 6s watch window (the deserialize failure lands later on a big rollout under load; the fork fails in 1–3s). Fix: watch until the TUI *settles* (composer **and** model·cwd status line, held 1s) or dies, with a 30s cap instead of a 6s window.
- **Fixed:** `codexErrorFromPane` required an `Error:` anchor; with a prompt on argv codex loses the head of the wrapped line to the alternate screen. Now falls back to the block above `Pane is dead`.
- **Fixed:** composer-only "settled" signal was false-positive — 0.153.4 draws the composer at ~250ms, before `thread/resume` resolves (failure at ~480ms). Status line + dwell required.

## Independent audit
`verification-auditor` → **PASS** on all six checks (`evidence/codex-resume-fails-loudly/audit/evidence.md`): bun 25/25, swift 5/5, offline SC2 failure at 1.6s with the full `unknown variant` text, offline SC3 settled, deployed resume→list→remain-on-exit off→close. Concerns raised and addressed in the same session: (1) `codexBin()` cached for the process lifetime → now re-resolves whenever any install's path/realpath/mtime changes (unit test `codexBin — re-resolves when an install changes`), re-deployed; (2) failure teardown order → managed row removed before the pane is killed. Accepted as documented: a pane that dies after the 30s cap is not caught (was 6s, now only for a pane still blank at 30s); with a prompt on argv the error text starts mid-path.

## Follow-ups (not in scope)
- ~~The Air~~ Done later in the session via the `air` ssh alias (Cloudflare; the `.local`/LAN names did not resolve): `bun install -g @openai/codex@0.153.4` (→ `~/.bun/bin/codex`, bun global dir `~/.bun/install/global`), `npm uninstall -g @openai/codex`, server restarted by port (respawned by its supervisor with the synced dirty tree = this same code; `md5 src/tmux.ts` matches the Pro). Found while verifying: every codex turn on the Air was "Blocked by hook" — `~/.codex/hooks.json` is synced but `~/.lfg/bin/lfg-agent-hook.py` is not; `scripts/install-agent-hooks.py` run there.
- Create/fork paths still tear down on bind timeout with a generic error; they could reuse `tmuxSetRemainOnExit` + `codexPaneFailure` to report codex's line too.
- Leftover artifacts: fork thread `01a07644-573e-72a3-8212-aa1865861042` (fiftyworkout, empty) in the codex list; scratch thread `01a0762b-…` (scratchpad cwd). Both harmless, deletable from the codex UI.
