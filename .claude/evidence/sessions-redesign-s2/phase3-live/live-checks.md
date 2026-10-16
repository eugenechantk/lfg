# Phase 3 live walk (SC12, SC11) — results, 2026-10-16

Rig: throwaway Claude session (Haiku) on the private `s2fixture` tmux socket, a scratch
`lfg serve` on 8795 (`LFG_AUTOPILOT=0`, `LFG_PUSH_WATCHER=0`, temp `LFG_DATA`), the
simulator (iPhone 17 Pro, `C47EB72F…`) pointed only at it, the bundled hosts file moved
aside. Torn down after: server stopped (8795 has no listener), tmux server killed, bundled
hosts file restored, the scratch host removed from the sim's prefs.

Each screenshot is the app as captured (414pt-wide downscale). `contact-w1-w24.png` shows
the first 24 side by side.

| # | Action (old menu → sheet) | Result | Evidence |
|---|---|---|---|
| 1 | Rename → pencil | Alert, save; title reads "S2 sheet walk" in the top bar, the sheet and the list | w6, w8, w15, w21 |
| 2 | Terminal tile | Opens the scratch host's shell ("Shell on Eugenes-MacBook-Pro"); ⌥ latches white and releases; Wide switches; the key row scrolls when a swipe starts on a key, without firing a key; ⌘V pastes the pasteboard ("live", copied from the sheet footer) | w11–w14, w29, w30, w34 |
| 3 | Files & links tile | Sheet opens (this session shared no files: "Files 0 / Links 0") | w8 |
| 4 | Subagents tile | Dimmed with none (w2); after the session ran one Agent call, badge "1", sheet lists "Count to three · Counted to three · general-purpose · 2s"; the row opens its transcript | w2, w22–w24 |
| 5 | Sign in tile | Sign-in requests sheet opens (empty) | w10 |
| 6 | Browser preview tile | Dimmed (no frame) | w2 |
| 7 | iPhone preview tile | Sheet opens | w9 |
| 8 | Model row | Menu lists Claude models and "Switch to Codex"; Sonnet picked; composer chip reads "Sonnet · Low" | w4, w5, w7 |
| 9 | Effort segments | Low selected; composer chip follows | w3, w7 |
| 10 | Host row | One host on the rig: shows the name only, no move (moving to a real host not exercised) | w15 |
| 11 | Fork row | Request sent; server refused with 409 "session is live on another host" because prod also claims the transcript (rig artifact: the synced `~/.claude/projects`). The app shows a "Fork failed" banner, not a silent drop | w17 |
| 12 | Mark as unread | View pops; the list shows "S2 sheet walk" under Unread | w20, w21 |
| 13 | Stop current turn (while busy) | Row appears only while busy; tapping it interrupted the turn (`[Request interrupted by user for tool use]`) | w18, w19 |
| 14 | End session | "End this session?" confirm; the tmux session `live` ended (`tmux -L s2fixture ls` no longer lists it); the view switches to "Continue in LFG" | w25, w26 |
| 15 | Footer copy | tmux name and id each land on the pasteboard (pasted into the composer earlier in the walk; pasted into the terminal with ⌘V, w34) | w34 |

Also seen: a long cwd wraps the sheet subtitle to four lines and pushes the tile grid down
instead of overlapping it (w31).

## SC11 (sign-in review step)

The delivery leg needs a waiting request from a connected Chrome target; the scratch rig has
none, so it was **not exercised live**. The review step was checked on the `signin` fixture
(two debug-only cookies): "Send this sign-in to Mac?", the login's own domain on and the other
off, "Send 1 cookie", then "Send 2 cookies" after switching the second domain on. Send was not
tapped. See `../phase3-r3-selfcheck/review-*.png`.

## Not covered

- Fork success path (blocked by the rig's two-host claim; covered by the existing fork tests
  and Phase 2's fork flow).
- Moving a session to another host (would touch a real host).
