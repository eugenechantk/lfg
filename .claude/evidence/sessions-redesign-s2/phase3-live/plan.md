# Phase 3 live walk (SC12, SC11) — plan

Rig: same as `phase2-live` (throwaway Haiku session on the private `s2fixture` tmux socket, scratch `lfg serve` on 8795 with `LFG_AUTOPILOT=0`, simulator pointed only at it, bundled hosts file moved aside and restored after). Open the session with `lfg://session/<id>`.

One tap per old ••• menu action, each checked on the far side:

| # | Action (old menu → sheet) | Check |
|---|---|---|
| 1 | Rename → pencil | alert, save, title changes in the top bar and list |
| 2 | Open Terminal → Terminal tile | terminal opens on the scratch host's shell; ⌥ latches; ⌘V pastes; Fit/Wide switches |
| 3 | Files & Links → tile | sheet opens with the session's files |
| 4 | Child sessions → Subagents tile | dimmed with no subagents; with one (ask the session for a Task), the sheet lists it with its result |
| 5 | Sign in on iPhone → tile | requests sheet opens |
| 6 | Show Browser Preview → tile | dimmed without a frame |
| 7 | iPhone Preview → tile | sheet opens |
| 8 | Model → Model row | menu opens; switch to Sonnet; session shows the new model |
| 9 | Effort → segments | tap Low; host confirms the effort change |
| 10 | Host → Host row | one host on the scratch rig: shows the name, nothing to move (moving to a real host is not exercised) |
| 11 | Fork session → row | a fork appears and opens; kill it after |
| 12 | Mark as unread → row | view pops; list shows the session unread |
| 13 | Stop → Stop current turn (while busy) | pane shows "Interrupted" |
| 14 | End session → row | confirm dialog; the tmux session ends |
| 15 | tmux / id copy → footer | pasteboard holds each value (paste into the composer, then clear) |

SC11: a waiting sign-in request needs a connected browser target; without one, check the review step on the fixture path (`LFG_S2_VIEW_FIXTURE=signin` → Sign in → "I'm signed in" → domain switches → "Send N cookies") and record that the delivery leg was not exercised.
