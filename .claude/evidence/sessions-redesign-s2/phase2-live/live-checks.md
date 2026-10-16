# Phase 2 live checks (2026-10-16)

## Rig

- Throwaway Claude Code 2.1.280 sessions (Haiku, hooks off) on a private tmux socket (`tmux -L s2fixture`), in a scratch folder. Production lfg scans only the default socket, so it never drove them.
- The worktree's `lfg serve` on port 8795, with `LFG_DATA` in the scratchpad, `LFG_PUSH_WATCHER=0`, `LFG_AUTOPILOT=0` and `TMUX=/private/tmp/tmux-501/s2fixture,0,0`. It could see and drive only the test panes; every real session reported `tmuxTarget: null`.
- The simulator app built from this worktree with only that host (`-lfg.hosts`), the bundled hosts file moved aside and restored afterwards.
- Sessions opened with `lfg://session/<id>`.

## Results

| SC | Check | Result | Evidence |
|---|---|---|---|
| SC7 | Stop is the send button while working | PASS — black square on a light disc | `live3.png` |
| SC7 | Typing turns it into Send | PASS | `live4.png` |
| SC7 | Stop really interrupts | PASS — pane "Interrupted · What should Claude do instead?", app idle | `live10.png` |
| SC8 | A mid-turn send shows in the strip; the transcript does not move | PASS — spinner row, "1 queued" in the top bar | `live8.png` |
| SC8 | The row's menu opens at the row | PASS — "Already with Claude", Send now | `live20.png` |
| SC8 | Send now works | PASS after fix 3 below — `send-now-native-started`, one user turn in the transcript | `live21.png`, `live44.png`, `sendq.log` |
| SC8 | Edit/Remove only while lfg holds the message | PASS — host offline: Try sending now / Edit / Remove; Claude-held: Send now only | `live48.png`, `live49.png`, `live20.png` |
| SC8 | Edit | PASS — row leaves the strip, text back in the composer | `live50.png` |
| SC8 | Remove | PASS | `live52.png` |
| SC8 | Held message sends when the host returns | PASS — delivered once | `sendq.log` 21:34:49 |
| SC8 | Failed send shows "Not sent" | PASS — seeded outbox row (`state='failed'`, 2 days old; the throw path itself was not exercised) | `live64.png` |
| SC8 | Retry / Delete | PASS — Retry delivered once, Claude replied "retry-ok"; Delete removed the row and the outbox row | `live65.png`, `live67.png` |
| SC9 | Permission: Allow once | PASS — `out.txt` created | `live56.png`, `live57.png` |
| SC9 | Permission: Deny | PASS — `out2.txt` not created, Claude interrupted | `live62.png` |
| SC9 | Question: option tap | PASS — "MIT (Recommended)" answered | `live68.png` |
| SC9 | Plan: Approve | PASS — Claude carried out the plan (LICENSE created) | `live69.png` |
| SC10 | "Type something else…" answers with free text | PASS — answered "Teal", Claude replied "Teal" | `live59.png`–`live61.png` |
| SC5 | List and view agree on "Working · time" | PASS after fix 2 — list 10s at a 10s-old turn; view 1m 33s vs list 1m | `live13.png`, `live16.png` |

Sign-in (SC9's fourth kind, SC11) is Phase 3.

## Bugs found and fixed

1. **Stray "Used" step.** A message absorbed mid-tool lands between the call and its result, so the result started its own empty step. Fixed in `TranscriptStepGrouper`: a late result joins the step that holds its call. Test from the live transcript shape. `live6.png` (before), `live17.png` (after).
2. **List "Working" time was the process start.** The list said 3m while the view said 45s. The server now sends `lastUserAt` (newest genuine user turn; absorbed messages and the interrupt marker don't count), and both list and view use `SessionStore.turnStartedAt`, which also reads messages the journal streamed since the last 60s refresh. Tests on both sides.
3. **Send now typed a held message twice.** Escape on a running tool makes Claude write "[Request interrupted by user for tool use]". The server matched only "[Request interrupted by user]", so it never saw Claude start the queued message itself, waited 5s, and retyped it. Fixed in `claudeInterruptResolution` (sendq.ts), test from the live lines.
4. **App hang (seen once).** Main thread at 100% CPU in lazy-stack layout for minutes, starting within 1.5s of fix 3's duplicate retype briefly re-showing the queued row. Not reproduced in four tries. The strip spinner started `withAnimation(.repeatForever)` in `onAppear`, a known way for a repeat-forever transaction to capture other layout changes; it is now clock-driven (`TimelineView`). Sample: `hang-sample.txt`. Residual risk: root cause unproven.
5. **"Always allow" link cut mid-path.** The pane wraps the option; the head arrived as the label. Now rejoined, and reads "Always allow access to this folder". `live62.png`.
6. **An answered question showed as "Used".** New step kind: "Asked · <question>", question in the prose font. `live63.png`.
7. **Questions read from the transcript had no typed-answer field.** The transcript's options omit Claude's built-in "Type something."; the host types into that row from the pane anyway, so the field now shows for every Claude question.

## Not fixed (pre-existing, logged for later)

- The scraped preamble above a question can include pane chrome: spinner lines, a tip, the tail of the user's prompt (`live70.png`). Server `contextAbovePrompt`.
- The pane parser misses the question's "☐ Header" chip on the pane path, so the label reads "Claude is asking" without the header.
- A deep link to a session the app hasn't listed yet shows "Opening session…" until the 60s refresh.
- An interrupt shows as a user bubble reading "[Request interrupted by user for tool use]".
- Inline predictive text was committed into a sent message once (simulator hardware keyboard).
