# Diagnosis — follow-up messages failing to send (2026-08-04)

Reported: "I keep having difficulties sending follow up messages to this Claude
Code session on this tmux `cy-224353-78784`."

Two independent bugs, both real, both now fixed. The first blocks sends with a
409; the second silently strands them. The second is the one actually biting.

## Bug 1 — detached forks steal their ancestor's tmux pane

**Fingerprint:** a session row with `tmuxName` set but `tmuxTarget: null`; the
iOS client 409s on send with no explanation.

`tmuxTargetForPid` resolved a pid to a pane by walking its parent chain until it
hit a `pane_pid`. Claude Code 2.1.x spawns detached children — a transient
daemon (`claude daemon run`), a `bg-pty-host`, `bg-spare` workers, and the
forked/branched agents the daemon hosts (`--fork-session --resume
--reply-on-resume`). Every one of those has the pane's `claude` in its ancestry,
so each resolved to the same pane and lfg listed several sessions claiming it.

The pane-collision guard in `listSessions()` then does the safe thing — it
can't tell which row is the live foreground, so it drops the target from *all*
of them, including the real session. The user's follow-ups die there.

Observed on this host: pane `cy-224353-78784:0.0` was claimed by both pid 79040
(the real TUI, `tty ttys011`) and pid 90707 (a detached branch agent, `tty ??`).

**Fix:** the controlling terminal is the discriminator. A pane's foreground
program shares the pane's tty; a daemon-spawned child has none.
`tmuxTargetForPid` now requires `ttyOf(pid)` to match the pane's `pane_tty`.
- `procinfo.ts` — the shared `ps` snapshot gained a `tty` column (no extra
  spawn); new `ttyOf()`, `normalizeTty()`, `ttyNameFromTtyNr()` (Linux decodes
  `/proc/<pid>/stat` field 7).
- `tmux.ts` — `paneMap` records `pane_tty` alongside the target.

This subsumes the codex-delegation hazard already noted in project CLAUDE.md:
the rule is not codex-specific, it is *any* detached descendant.

## Bug 2 — the composer region parsed as empty, so every send retried and failed

**Fingerprint:** queue status `failed`, error `message never left the input box
after retries`, `attempts: 3`. Watching the pane shows the text being typed in
correctly, sitting there, being cleared, and retyped — three times.

`deliver()` confirms its text landed by substring-matching against
`inputBoxText()`, which returns the region between the composer's two `─`
border lines. That parser paired rule lines bottom-up, and `RULE_RE` required
a line to *start* with `─{3,}`. Two real pane shapes defeated it, and in both
the region came back as the **empty string** — which reads as "our text never
landed", so `deliver()` retyped and eventually failed. The keystrokes were
arriving perfectly the whole time.

1. **A border drawn wider than the pane wraps into two consecutive rule lines.**
   The scan paired the wrap continuation with its own first half, collapsing the
   region to nothing:
   ```
   ─────────────────────────────────────────────  <- bottom border (77 cols)
   ────────                                       <- its wrapped remainder
   ```
2. **Claude's branch view labels the top border `(Branch) ──`** — the label is a
   *prefix* with only two trailing dashes, so `^─{3,}` never matched it. Even
   with (1) fixed, the top border would still be invisible.

Both panes Eugene reported trouble with were in branch view.

**Fix (`tmux.ts`):**
- `isRuleLine()` replaces `RULE_RE`. A border ends in dashes, holds ≥2 dashes,
  carries ≤40 non-dash chars of label, and never contains `❯`. This admits
  plain borders, centred session-name labels, and `(Branch) ──` alike.
- `inputBoxFromPane()` collapses each maximal *run* of rule lines into one
  border before pairing, so a wrapped border can't pair with itself. Split out
  from `inputBoxText` so it can be tested against captured panes.

## Verification

- `bun test` — 163 pass, 0 fail (13 new tests across
  `src/tmux-pane-tty.test.ts` and `src/tmux-composer-border.test.ts`, all built
  from verbatim `ps` / `tmux capture-pane` output from the failing host).
- Live process table: the detached fork and daemon workers resolve to no pane;
  all 8 real panes keep their targets; `cy-224353-78784:0.0` restored to pid
  79040.
- Live composer parse: all 8 panes now return their real composer contents. The
  two previously returning `""` are correct. One pane returns `null` — correct,
  it is showing a scrolled output view with no composer on screen.
- **Real send, end to end:** `POST /api/sessions/<id>/send` to the branch pane
  `cy-222138-60277` reached `delivered` in <2s; the pane shows the message
  submitted and answered. The same pane failed all 3 attempts before the fix.

## Bug 3 — branch conversations were unsendable (regression from Bug 1's fix)

**Fingerprint:** `POST /api/sessions/<branch-id>/send` → `session is not in a
tmux pane — cannot send`; the iOS client shows the message in a blue bubble
with an error and a Try Again button.

Bug 1's fix gated pane resolution on the controlling terminal. That encoded
"the pane's conversation is the process holding its tty" — which is **false for
branch view**. Claude Code runs the fronted branch in a *detached* child and
proxies the pane's input to it, so the branch has no tty and was excluded
outright. It thereby lost the target and became unsendable, while the parent
TUI — which the pane is *not* currently fronting — kept it.

Verified on pane `cy-224353-78784:0.0`: the pane draws `(Branch) ──` in its
composer border, and keys typed there are answered by `0b41d17c` (the branch),
not `a135bff5` (the parent whose pid owns the tty).

**Fix:** resolve the ambiguity where it belongs — at collision resolution, not
at pane lookup.
- `tmuxTargetForPid` is a pure ancestry walk again; several pids may legitimately
  resolve to one pane. `ttyOf` survives as a tiebreak, plus `paneTtyForTarget`.
- `resolvePaneOwners()` (new, in `sessions.ts`) replaces the old "drop the target
  from all of them" guard. Among candidates for a pane it keeps the most
  recently active *real conversation* (has a `sessionId` and a written
  transcript), so daemon/`bg-pty-host`/`bg-spare` workers can never win, and a
  stale parent loses to the live branch. Exactly one row per pane stays sendable.

**Why guessing beats refusing here:** the keystrokes reach whatever the pane
fronts either way — lfg only chooses which row it labels sendable and which
transcript `deliver()` confirms against. A wrong guess costs a confirmation
label (`queued` instead of `delivered`); refusing costs the entire feature.

**Verified:** all 9 live panes map one-to-one to exactly one sendable session;
a real send to `0b41d17c` reached `delivered` in <2s and the pane shows it
answered `ack`.

## Known remaining nuance

Attribution follows transcript recency, so immediately after a user switches a
pane between its parent and a branch — before the newly-fronted side has taken
a turn — lfg may still label the other side sendable. The message still lands
in whatever the pane fronts; only the confirmation is affected, and it surfaces
as a send that stays `queued` rather than reaching `delivered`. Modelling
branches as first-class rows (parent + branches, each with its own pane
affinity) is the durable fix and is a design decision, not a patch.

## Files

- `src/procinfo.ts` — tty in the ps snapshot; `ttyOf` / `normalizeTty` /
  `ttyNameFromTtyNr`; `parsePsRows` exported for tests
- `src/tmux.ts` — `PaneInfo` + `pane_tty` in `paneMap`; `parsePaneList`;
  tty-gated `tmuxTargetForPid`; `isRuleLine` + `inputBoxFromPane`
- `src/tmux-pane-tty.test.ts`, `src/tmux-composer-border.test.ts` — new
