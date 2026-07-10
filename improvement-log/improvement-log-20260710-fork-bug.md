# Improvement Log — Session 20260710-fork-bug

## Tracker

- [ ] 2026-07-10 — Nearly accepted the user's session-ID labels as ground truth; they were inverted
- [ ] 2026-07-10 — First root-cause theory was wrong; the disconfirming experiment saved the diagnosis
- [ ] 2026-07-10 — `codex-delegate` skill structurally breaks the parent lfg session's send path
- [ ] 2026-07-10 — Called a process "survived SIGHUP" 1s after kill-session; it was mid-shutdown

## Log

### 2026-07-10 — Nearly accepted the user's session-ID labels as ground truth

**What happened:** The bug report named "Original claude code: f95e468a" and "Forked claude
code: eb7d6e12". I started reasoning from those labels. Process argv showed the opposite:
`f95e468a` was spawned by `claude --resume eb7d6e12 --fork-session`, so it is the fork.

**Why this was wrong:** A bug report's identity claims are *observations through the buggy
UI*. When the bug is "the UI shows me the wrong session", the labels in the report are
themselves corrupted data. Reasoning from them propagates the bug into the diagnosis.

**What better looks like:** For any bug involving session/process/resource identity, resolve
identity from the system, not the report. `ps -eo pid,lstart,command` and the pidfiles took
30 seconds and settled it. Do that *before* forming any theory. Generalizes: treat user-supplied
IDs as hypotheses to verify, not facts — especially when the reported symptom is misattribution.

### 2026-07-10 — First root-cause theory was wrong; the disconfirming experiment saved it

**What happened:** I theorized that `~/.claude/sessions/<pid>.json` briefly holds the *pre-fork*
session id, so `forkSession`'s 500 ms poll grabs the source id and the client navigates to the
source. It was a tidy theory that explained all three symptoms at once. I named the check that
would falsify it (fork a small session, poll the pidfile every 200 ms, watch the id) and ran it.
The pidfile appears at ~1.0 s already carrying the new id. Theory dead.

**Why this mattered:** Had I written that up, the "fix" would have been a longer poll or a
re-read loop — touching correct code, leaving all three real bugs live. The memory
[[disconfirm-before-declaring-root-cause]] is what forced the experiment.

**What better looks like:** Keep doing this. A theory that explains *everything* elegantly is
the most dangerous kind — it earns an experiment, not a writeup. Note that the cost was ~40
seconds (spawn a throwaway fork of the smallest transcript on disk, poll, kill). Cheap
disconfirmation is almost always available; find the smallest instance of the thing.

### 2026-07-10 — `codex-delegate` structurally breaks the parent lfg session's send path

**What happened:** `lfg`'s `listSessions` gives every process named `codex` its own session row
and resolves its tmux target by walking up the ppid chain to a pane. The `codex-delegate` skill
(global CLAUDE.md routes all "execute-half" coding work to it) spawns `codex` *inside* a claude
pane. Two rows then claim the same pane, the pane-collision guard nulls `tmuxTarget` on both,
and `POST /api/sessions/:id/send` 409s. So: **using codex-delegate from an lfg session makes that
session unsendable from the iOS client for as long as codex runs.**

**Why this is worth persisting:** It is an emergent conflict between two systems that were each
correct in isolation — a global workflow policy and a session-enumeration heuristic. Neither
repo's docs mention the other. It cost real time here because the symptom ("can't send to the
fork") pointed at the fork feature, not at codex.

**What better looks like:** (1) Fix the enumeration to skip codex processes that are descendants
of an agent process. (2) Until then, when an lfg session appears unsendable, check for a `codex`
descendant of its pane pid before touching the fork/send code. Diagnostic fingerprint in
`/api/sessions`: `tmuxName` set but `tmuxTarget: null` means the collision guard fired — the
session is not broken, it is *ambiguous*, and something else is sharing its pane.

### 2026-07-10 — Called a process "survived SIGHUP" 1s after kill-session

**What happened:** After `tmux kill-session -t lfg-9c394e`, I slept 1s, saw pid 66934 still in
`ps`, saw its transcript mtime advance, and told Eugene the claude process "survived the SIGHUP
and is still writing." It hadn't — it was flushing its transcript and removing its pidfile on the
way out. A few seconds later it was gone on its own.

**Why this was wrong:** I sampled a shutdown in progress and reported it as a steady state. Claude
Code does meaningful teardown work (transcript flush, pidfile unlink) on SIGHUP, so "still present
in ps + file still being written" is the *expected* appearance of a clean exit, not evidence of a
zombie. I nearly escalated to `kill -9` on a process that was already dying.

**What better looks like:** After a kill, poll for absence with a timeout (`until ! ps -p $PID`)
rather than checking once. Only call a process "surviving" after it outlives a grace period —
several seconds for anything with teardown. And don't narrate an intermediate observation to the
user as a conclusion.
