# iOS Visual Evidence Audit

Verdict: PARTIAL. The audit was blocked, and no criterion was verified on the feature/ios-terminal build.
Timestamp: 2026-09-15 17:06-17:11 HKT
Repository: /Users/eugenechan/dev/personal/lfg/.worktrees/ios-terminal (feature/ios-terminal)
Simulator: iPhone 17 Pro, E0DC8228-3248-4630-8929-FBC5DFC6AE6D
App: com.eugenechan.lfg

## Change Audited
SC8 adds swipe scrolling through tmux copy-mode and removes the mouse-toggle button from the key bar. SC9 adds "Open Terminal" to the session ••• menu, opening the terminal on that session's host.

## Blocker
Another Claude Code session was driving the same simulator while this audit ran. It was session 5e420749, working on `transfer-from-offline-host` in the main checkout `/Users/eugenechan/dev/personal/lfg`.
- 09:07:18Z: it ran `flowdeck run --simulator E0DC8228…` from `/Users/eugenechan/dev/personal/lfg/ios`. That installed the main-checkout build over this worktree's build, and the new app launched at 09:07:25Z (`flowdeck-apps.json`, launch A0D40E3E).
- 09:08:33Z: it tapped (30,86) and closed the terminal this audit had open.
- 09:09:45Z onward: it was opening Settings and continuing its own flow.

After 09:07:25Z, every observation in this audit came from the wrong build. Reinstalling the worktree build would have broken that session's work, and it could reinstall its own build again partway through. So the audit stopped here.

## Success Criteria
| Criterion | Result | Evidence |
|---|---|---|
| SC8.1-5 swipe scroll, no stray input, type-back | NOT VERIFIED (blocked) | none on the correct build |
| SC8.6 no hand button; tap only focuses | NOT VERIFIED on the worktree build. On the main-checkout build a tap PASTED tmux buffer0 into the shell | 03-reopened-keybar.png, 04-capture-after-tap-PASTE-BUG.txt |
| SC9 Open Terminal opens the session's host | NOT VERIFIED (blocked) | none |
| Regression: reattach | Server side only: reopening attached to the same pane PID 30538 (on the wrong build) | 02-terminal-opened.jpg |

## Observations (main-checkout build, not the audited build)
- The key bar shows the blue hand (mouse toggle), and F1 is missing (03). The only frame from the worktree build was taken at 09:07:19Z, before the reinstall. It showed F1 and no hand, but that frame was not kept.
- A single synthetic tap at (200,400) on the terminal pasted tmux `buffer0` (a Noto podcast reply) into zsh, leaving it at a `∙` continuation prompt (04). This is BUG3 as described in the feature doc, reproduced on a build without the fix. It shows why SC8.6 matters. It does not show that the worktree build regressed.
- Cleanup: sent `C-c` to `lfg-term-phone` to clear the pasted continuation (06). The 9982 server was left running (pid 10891).

## Artifacts
- 01-session-list.jpg
- 02-terminal-opened.jpg (wrong build)
- 03-reopened-keybar.png (wrong build: hand button)
- 04-after-tap-paste-bug.png (the other session had already closed the terminal by then), 04-capture-after-tap-PASTE-BUG.txt
- 05-terminal-dismissed-by-other-session.jpg
- 06-capture-after-ctrl-c-cleanup.txt
- flowdeck-apps.json

## Commands
- `flowdeck config get --json`, `flowdeck apps --json`
- `FLOWDECK_UI_SKIP_LOCK_CHECK=1 flowdeck ui simulator session start|stop -S E0DC8228-3248-4630-8929-FBC5DFC6AE6D`
- `… touch down/up 30,86`, `… tap terminalButton`, `… tap --point 200,400`, `… type 'clear; seq 1 400'`, `… key 40`, `… screen --output`
- `tmux display -p -t lfg-term-phone '#{pane_pid} #{pane_in_mode} #{scroll_position}'`, `tmux capture-pane -p`, `tmux list-buffers`

## Notes
Re-run this audit once the simulator is free. Either wait for session 5e420749 to finish, or give each session its own simulator. First reinstall the worktree build with `flowdeck run` from the worktree's `ios/`, then confirm the key bar shows F1 and no hand before testing anything.
