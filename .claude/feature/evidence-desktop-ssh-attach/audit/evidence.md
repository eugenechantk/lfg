# Verification Audit

Verdict: PASS
Timestamp: 2026-07-13 02:47–02:58 HKT
Repository: /Users/eugenechan/dev/personal/lfg/.claude/worktrees/desktop-ssh-attach-transfer
Surface: mixed (macOS desktop app CLI hook + HTTP APIs + ssh/tmux; UI layer judged by code — screen locked)
Auditor: independent verification-auditor subagent (Air, Eugenes-MacBook-Air.local)

## Change Audited

`desktop/LFGSessions.swift` only (514+/29-). Remote tmux sessions open via ssh-attach in iTerm; context menu adds "Resume locally" and "Move to <host>"; move = close on source → wait transcript sync (90 s, 3 s poll, 1 s epsilon) → resume on target; hidden `--move-test <id> <src> <tgt>` runs the real MoveCoordinator headlessly.

## Success Criteria

| Criterion | Declared Method | Result | Evidence |
|---|---|---|---|
| Build compiles clean | `cd desktop && ./build.sh` | PASS | 01-build.log (exit 0) |
| SC1 ssh-attach to remote tmux | E2E click + remote list-clients | PASS (all seams except in-app click — screen locked, judged by code) | 02-diff.patch (open() remote branch → sshAttachCommand), 08-sc1-binary-strings.log (template in shipped binary), 09-sc1-ssh-attach-live.log (exact command form attached live client `/dev/ttys067` to Pro `cy-015218-35822`, pane capture shows live remote session, detach verified after kill) |
| SC2 local attach unchanged | E2E click local row | PASS (code inspection only — locked screen) | 02-diff.patch: `hostIsLocal + tmuxName` branch is unchanged context lines (`shq(tmux) attach-session -t shq(name)`) |
| SC3 hosts.json string/object + ssh fallback | parse check + code review | PASS (real decoder exercised) | 10-sc3-hosts-decoder.log — verbatim-extracted Config source compiled and run: string entry → `eugenechan@localhost`, object w/ ssh → ssh value, object w/o ssh → `eugenechan@100.99.1.2`. Live `~/.config/lfg-desktop/hosts.json` is the mixed format; both hosts served sessions over HTTP |
| SC4 move to host | E2E disposable session | PASS (full live E2E, reproduced independently) | 03/04/05: session `47b91875…` created on Air, `--move-test` → `{"ok":true}` exit 0 in 4.4 s; Air no longer lists it, local tmux `lfg-18344f` gone; Pro runs `claude --resume 47b91875…` in managed tmux `lfg-bbf28e`; Pro transcript has marker (grep -c AUDIT-TEST → 4) |
| SC5 busy confirm; cancel = no API calls | code review + spot check | PASS (code inspection only — UI alert, locked screen) | 02-diff.patch: `requestMove` gates `item.status == .working` (= `session.busy`) → `pendingMove` alert; Cancel only nils `pendingMove`; every network call lives in `startMove → store.move`. `--move-test` bypasses this by design (UI-layer guard) |
| SC6 failures surface per step | simulate + code review | PASS (2 of 3 paths live) | 06-sc6-bogus-id-negative.log: bogus id → `{"ok":false,"error":"Move failed at close: HTTP 404: …session not found…"}` exit 1, host counts unchanged. 11-sc6-sync-timeout.log: unreachable target → exactly 90 s → `"Closed on localhost, but the transcript hasn't synced to 127.0.0.1 yet. The session is safe — resume it there once sync catches up."` exit 1, no resume attempted. 12-sc6-timeout-aftermath.log: session closed but present in `/api/sessions/resumable` — the "safe" claim holds. Resume-error path: code + 08 strings (`Move failed at resume:`). UI-side unreachable targets are excluded by eligibility (`host.error == nil`) |
| SC7 "Resume locally" context menu | E2E invoke | PASS (code inspection only — locked screen) | 02-diff.patch: contextMenu shows "Resume locally" for `!hostIsLocal && sessionId != nil`; `Opener.resumeLocally` is the extracted pre-existing resume body (unchanged context lines: `lfgd-` tmux + `claude --resume`) |

## Artifacts

All under `.claude/feature/evidence-desktop-ssh-attach/audit/`:
01-build.log, 02-diff.patch, 03-sc4-create-session.json, 04-sc4-move-test-run.log, 05-sc4-poststate-both-hosts.log, 06-sc6-bogus-id-negative.log, 07-cleanup-disposable.log, 08-sc1-binary-strings.log, 09-sc1-ssh-attach-live.log, 10-sc3-hosts-decoder.log, 11-sc6-sync-timeout.log, 12-sc6-timeout-aftermath.log, 13-cleanup-orphan-pro.log

## Commands

- Build: `cd desktop && ./build.sh`
- Disposable session: `curl -X POST http://localhost:8766/api/sessions/new -d '{"cwd":"/Users/eugenechan","agent":"claude","prompt":"Reply with exactly: AUDIT-TEST"}'`
- Move E2E: `./desktop/build/lfg.app/Contents/MacOS/lfg --move-test 47b91875-… http://localhost:8766 http://100.120.101.14:8766`
- Negative: same with `00000000-dead-beef-0000-000000000000` → exit 1
- Timeout path: `--move-test 1cf1b11c-… http://localhost:8766 http://127.0.0.1:9999` → 90 s → exit 1
- SSH seam: `tmux new-session -d -s audit-ssh-attach -x 220 -y 100 <script running: ssh -t -o ConnectTimeout=5 'eugenechan@eugenes-macbook-pro-2' 'PATH=/opt/homebrew/bin:/usr/local/bin:$PATH tmux attach-session -t '\''cy-015218-35822'\'''>`; verify `tmux list-clients` on Pro; kill local session; verify detach. No keystrokes sent; oversized client (220x100) so the user's remote view was never shrunk.
- Cleanup: `POST /api/sessions/<id>/close` on Pro; orphaned pid 25274 killed via ssh after API refused (see Notes). Both hosts verified back to pre-audit session counts (Air 30, Pro 56); no stray processes matching either audit session id on either host.

## Notes

- **Screen locked**: SC1 in-app click, SC2 click, SC5 alert render/cancel, SC7 menu render were judged by code inspection of the diff per the caller's constraint. Every other seam (ssh command, remote attach/detach, full move flow, all three CLI-reachable error paths, config decoding) was exercised live.
- **Out-of-scope server finding (not the desktop change; does not affect the verdict):** `POST /api/sessions/<id>/close` on the Pro against the *resumed managed-tmux* session killed the tmux but orphaned the `claude --resume` process (pid 25274), which the server then re-listed as an unmanaged session that `/close` refuses (`"session is not in a tmux pane — cannot close"`); manual `kill -9` over ssh was required. The move flow's own source-side close on the Air left no orphan (verified by `ps`). Worth a server-side look — a user who moves a session and later closes it on the target may hit this.
- `--move-test` bypasses *all* UI eligibility guards (agent type, target reachability, same-host), not only the busy confirm the feature doc mentions. UI path enforces them via `moveTargets`. Test-hook-only surface; acceptable, but worth knowing.
- Implementer's evidence reproduced faithfully: move timing (3.6 s claimed, 4.4 s observed), close-404 JSON shape, binary strings, sync-timeout wording all match. Short UI strings ("Resume locally", "Move to") are Swift small-strings and legitimately absent from `strings` output; they are present in the diff.
