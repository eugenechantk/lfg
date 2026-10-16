# Desktop list: out-of-sync rows (report) and copy IDs (done)

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

## Next step when it recurs

1. Right-click the row → Copy session ID; note the clock time and which group it sat in.
2. `grep <id8> ~/.config/lfg-desktop/desktop-list.log` and the host's journal for that id around that time.
3. If the server said busy and the desktop drew idle (or the reverse) with no refresh in between, it is poll lag: the fix is the journal stream on the desktop, as the phone has. If the server itself was wrong, it is a pump bug (pane scrape or transcript freshness).

## Decision Log

- 2026-10-16 — Did not change the poll interval or add a stream without a reproduction: the log costs nothing and tells which side is wrong.
