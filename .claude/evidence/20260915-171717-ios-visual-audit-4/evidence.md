# iOS Visual Evidence Audit
Verdict: PASS (with header-format note, see Notes)
Timestamp: 2026-09-15 17:17-17:23 local
Repository: /Users/eugenechan/dev/personal/lfg/.worktrees/ios-terminal (feature/ios-terminal, uncommitted Iteration 2 changes)
Simulator: cc-48a12e88-iphone, 72C21E2D-90BE-49AA-92B1-1F9F6CE7CD17 (dedicated)
App: lfg (scheme LFG), installed build from this worktree (not rebuilt)

## Change Audited
Iteration 2: vertical swipe scrolls tmux history (SC8); session detail ••• menu "Open Terminal" opens the session's host (SC9).

## Success Criteria
| Criterion | Result | Evidence |
|---|---|---|
| Right build: key bar esc, ctrl, tab, ~, \|, /, -, F1, arrows, no hand button | PASS | 02-terminal-scratch.jpg (tree: no extra button) |
| SC8.1 terminalButton opens Scratch host | PASS* | 02-terminal-scratch.jpg (header "Scratch"; *no hostname-over-URL subtitle exists); 22-client-owner.txt (client parent = 9982 server pid 57499) |
| SC8.2 swipe down shows older lines + [N/M]; swipe up goes back; flick | PASS | sc8-swipe-scroll.mov, 04/05/06/07/08-*.jpg ([58/404], [123/404], [53/404]) |
| SC8.3 pane_in_mode=1, position tracks swipes | PASS | tmux-log.txt: 0 -> 29 -> 58 -> (up) 34 -> (flick) 123 -> (up) 88 -> 53; up at bottom exits mode (8 -> 0) |
| SC8.4 swipes/tap never type or paste | PASS | tmux-log.txt: horizontal L/R + single tap kept pos=53, prompt line stayed empty "❯"; swipe up on live screen: no history recall; buffer count unchanged (1 pre-existing buffer never pasted) |
| SC8.5 type while scrolled returns live, prints AUDIT4_42, nothing lost | PASS | 11-typed-while-scrolled.jpg, 12-audit4-42-live.jpg, 12-pane-after-echo.txt; scrollback holds 1..400 contiguous (count=400, misordered=0) |
| SC9 menu has Open Terminal | PASS | 18-menu-open-terminal.jpg |
| SC9 opens session's host (Pro), not default | PASS | 19-menu-terminal-pro.jpg (header "Eugenes-MacBook-Pro"), 20-host-menu-pro.jpg (Pro checked), 19-client-owner.txt (tmux client spawned 17:21:05 by 8766 production server) |
| SC9 connects (prompt + tmux client) | PASS | 19-menu-terminal-pro.jpg, 19-client-owner.txt |
| SC9 close returns to session detail | PASS | 21-closed-back-to-detail.jpg |
| SC9 contrast: list terminalButton opens Scratch | PASS | 22-list-terminal-default-scratch.png, 22-client-owner.txt |
| Regression: typing responsive | PASS | typing-latency.txt (text in tmux pane <=7 ms after FlowDeck type returned), 16-typing-regress-ok.jpg |
| Regression: close + reopen reattaches | PASS | 14-closed-list.jpg, 15-reopened-scratch.jpg (seq + AUDIT4_42 still visible) |

## Artifacts
All files in this directory; video sc8-swipe-scroll.mov (h264, 75 s, covers steps 04-11).

## Commands
- flowdeck config get --json (saved config points at E0DC8228; overridden with -S on every call, config untouched)
- FLOWDECK_UI_SKIP_LOCK_CHECK=1 flowdeck ui simulator session start -S 72C21E2D-90BE-49AA-92B1-1F9F6CE7CD17 --json
- flowdeck ui simulator tap terminalButton / type / key 40 / swipe --from --to --duration / tap --point / touch down|up 359,84 / tap "Open Terminal" / tap Host / tap Close / back / screen / record --codec h264 -t 75
- tmux display -p '#{pane_in_mode} #{scroll_position}', capture-pane, list-clients -F, ps for client parent

## Notes
- Header format: the terminal header shows only the saved host name ("Scratch" for 127.0.0.1:9982, "Eugenes-MacBook-Pro" for the Pro host). There is no second line with the hostname or URL as the brief described. Host identity was proven by the Host menu checkmark and by which server process spawned the tmux client.
- Swipes were synthetic FlowDeck drags. Slow drags moved about 29 lines each and a 0.12 s flick moved 65, so momentum is present. Real-finger feel is not proven.
- Pro terminal first frame: the tmux status bar sat mid-screen (y≈693) with blank space below. The next capture filled the screen, so it is likely an initial resize that settled. Low risk.
- Side effect: while navigating back, a stale-tree tap opened the session "I am missing gpt-6 astra…" (marking it read). No message was sent and nothing was changed.
