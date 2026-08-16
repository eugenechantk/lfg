# Bug 005: Codex CLI sessions do not auto-rename

## Status: WONT_FIX

## Description

Codex CLI sessions appear not to receive generated titles on every autopilot
tick, while the expected behavior was initially understood as periodic forced
renaming.

## Steps to Reproduce

1. Start a Codex CLI session from the iOS client.
2. Exchange enough messages to establish a clear task topic.
3. Leave the session running across multiple autopilot tick intervals.
4. Refresh the iOS session list.
5. Observe that the Codex title remains unchanged instead of being regenerated.

## Root Cause

Autopilot is agent-agnostic and does include Codex transcripts. It is a
drift-based retitler, not a forced periodic renamer: a session must be owned by
the current host, have at least three meaningful recent user turns, have grown
by at least 2 KiB since its prior checkpoint, and the title model must conclude
that the topic changed. Human-set titles are never overwritten.

The current Codex session proves the path is active: autopilot renamed
`01a00041-dc1a-7990-b9cd-af072bb403cb` from `Session behavior testing` to
`iOS session permission bypass` at 2026-08-16 03:06 local time.

## Success Criteria

- Confirm Codex sessions enter the same candidate pipeline as Claude sessions.
- Confirm a live Codex session has an `auto` title record written by autopilot.
- Document why eligible sessions may correctly retain their current title.

## Investigation Log

### Attempt 1

**Hypothesis:** Autopilot title refresh explicitly filters out Codex sessions, or
the title generator cannot obtain eligible user/assistant messages from Codex
transcripts.

**Changes:** None; tracing the tick scheduler and title update pipeline.

**Result:** No agent filter excludes Codex. Multiple Codex sessions have `auto`
title records, and the current permission-debugging session was renamed during
this investigation. No code change is required for the reported behavior.

### Attempt 2

**Hypothesis:** Codex transcript volume can make some candidates too thin within
the retitler's bounded recent-message scan.

**Changes:** None; measured the recent-turn digest for every live Codex session.

**Result:** Confirmed as a limitation, not the cause of the current session's
behavior. Large Codex rollouts can expose fewer than three recent user turns
inside the 4 MiB scan budget, so those sessions are deliberately skipped rather
than renamed from weak evidence. Changing that threshold would be a product
policy change and is outside this permission-mode fix.
