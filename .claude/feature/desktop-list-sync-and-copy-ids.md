# Desktop list: out-of-sync rows (fixed) and copy IDs (done)

## Reports (Eugene, 2026-10-16)

1. A working session's row reads "Ready for your next message" with "Nm ago" in the time column.
2. A row in Recent carries a "Working" status line.

## Ground truth so far

- Group and status line both derive from one value (`SessionItem.status` → `s2State` → `DesktopSessionList.group` / `.line`), so within one render they cannot disagree. A Recent row reading "Working" therefore needs a second source: an animation frame mid-regroup, a stale row image, or a state I have not seen.
- Checked live at 19:10: the server's `busy` flag matched every recent session's pane (two mid-turn, the rest at the prompt), and the desktop drew exactly that. Not reproducible on demand.
- The desktop polls every 10 s (`Timer.publish(every: 10)`); the server's `busy` comes from the pump about once a second. A row can read idle for up to ~11 s after a turn starts, and Working for up to ~11 s after it ends. That alone explains report 1 for short sightings, not report 2.

## What shipped (commit on `perf-closed-and-new-sessions`)

- Right-click → "Copy session ID" / "Copy tmux name" (ids `copy_session_id`, `copy_tmux_name`), the phone sheet's tap-to-copy equivalent.
- `~/.config/lfg-desktop/desktop-list.log`: one line per session whose list state changed at a refresh — status, busy, closed, offline, group, seconds since last activity. Next sighting: copy the id from the row, note the time, and read the line for that id against the host's journal (`GET /api/events/page`).

## Root cause and fix (2026-10-16, later)

Eugene's screenshot showed both directions at once: "Ready for your next message" rows under Working with a grey time, and "● Working" rows under Recent with a green time. The row *content* was internally consistent and old; only the header placement was new. The rows are drawn by `ForEach(g.items)` per group inside one `LazyVStack`, keyed by the item id alone. When a session changes group, the lazy stack keeps the old row view for that id under the new header and does not redraw it (a row that stays in its group does redraw: the `(flipped)` title probe).

Reproduced deterministically with `lfg --window-shot 400 out.png --board --flip`: after the first draw the fixture flips two Working rows idle and brings a closed row back busy. Before the fix, "Reelly creative fatigue check" sat under Recent still reading green "9m ago · Working" (`evidence/desktop-sync/flip-before-fix-2.png`). Fix: each row's identity carries its group (`.id("\(group):\(item.id)")`), so a move is a new view. After: the moved row reads grey "now · Ready for your next message" (`flip-after-fix.png`); the static board shot is byte-identical to before.

Also seen in the screenshot, not fixed here: the same closed session listed twice in Recent ("make sure you're committing…", 11m and 1h). Likely two hosts each returning the synced transcript as closed (lease sync lag on the Air). Separate follow-up.

## Next step when it recurs

1. Right-click the row → Copy session ID; note the clock time and which group it sat in.
2. `grep <id8> ~/.config/lfg-desktop/desktop-list.log` and the host's journal for that id around that time.
3. If the server said busy and the desktop drew idle (or the reverse) with no refresh in between, it is poll lag: the fix is the journal stream on the desktop, as the phone has. If the server itself was wrong, it is a pump bug (pane scrape or transcript freshness).

## Decision Log

- 2026-10-16 — Did not change the poll interval or add a stream without a reproduction: the log costs nothing and tells which side is wrong.
