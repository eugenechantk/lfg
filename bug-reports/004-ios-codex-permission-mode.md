# Bug 004: iOS-created Codex sessions sometimes require manual approval

## Status: INVESTIGATING

## Description

Some Claude Code CLI and Codex CLI sessions started from the iOS client actually
run in manual approval mode instead of bypass-permissions mode. This is distinct
from the Codex `Main [default]` collaboration-mode label.

## Steps to Reproduce

1. Open LFG on iOS and create a Codex session.
2. Select a repository, model, and initial prompt.
3. Let Codex attempt a command or file mutation that normally requires approval.
4. Observe whether the session runs with danger-full-access and never asks, or
   presents an approval/manual-mode requirement.
5. Repeat across new, resumed, and forked Codex sessions.

## Root Cause

The macOS LFG app's local closed-session opener used plain
`claude --resume <id>` and `codex resume <id>`. Unlike the server-managed create,
resume, and fork helpers, this desktop-only path omitted the CLI bypass flags.
The resulting `lfgd-*` sessions are then discovered by the LFG server and shown
on iOS, making them look like iOS-created sessions even though the process was
spawned by the desktop app.

Every server-managed Codex lifecycle path inspected—create, resume, and fork—uses
`--sandbox danger-full-access --ask-for-approval never`. The Codex AI SDK path
likewise uses `sandboxPolicy: danger-full-access`, `approvalPolicy: never`, and
`autoApprove: true`. The iOS request contains no permission-mode override.

The authoritative `turn_context` records for the three currently managed Codex
sessions, plus all 353 turn contexts recorded from August 14–16, 2026, report
`approval_policy=never`, `sandbox_policy=danger-full-access`, and
`collaboration_mode=default`.

## Success Criteria

- Document that `Main`/`Plan` and approval/sandbox policy are separate settings.
- Confirm current create, resume, fork, and AI SDK paths use full-access policy.
- Confirm recent authoritative turn contexts do not contain a policy mismatch.
- Ensure desktop-resumed Claude uses `--dangerously-skip-permissions`.
- Ensure desktop-resumed Codex uses `--sandbox danger-full-access`,
  `--ask-for-approval never`, and `--dangerously-bypass-hook-trust`.
- If an actual approval prompt recurs, capture the affected LFG session ID and
  inspect that session's rollout record rather than inferring policy from the
  footer.

## Investigation Log

### Attempt 1

**Hypothesis:** One iOS lifecycle path or backend selection does not use the same
Codex spawn arguments as the normal managed Codex creation path.

**Changes:** None; tracing request payloads, backend selection, and live process
arguments first.

**Result:** No divergent lifecycle path was found. Current managed CLI process
arguments and rollout records agree on never-ask, danger-full-access policy.

### Attempt 2

**Hypothesis:** The problem occurred intermittently in recent turns even though
the currently running sessions have the expected policy.

**Changes:** None; scanned recent Codex rollout `turn_context` records.

**Result:** All 353 turn contexts from August 14–16, 2026 use
`never / danger-full-access / default`. The first two values are the permission
policy; the last is collaboration mode.

### Attempt 3

**Hypothesis:** A launch path outside the previously inspected managed Codex
helpers starts Claude or Codex without bypass flags, or existing tmux sessions
are being adopted/resumed without normalizing their launch policy.

**Changes:** None; inspecting all live Claude/Codex process arguments and every
new, resume, fork, adoption, and reconnect path.

**Result:** In progress.

### Attempt 4

**Hypothesis:** The `lfgd-*` processes are spawned by the macOS desktop client's
local resume path rather than the server's iOS-facing resume endpoint.

**Changes:** Updated `Opener.resumeAgentCommand` so both Claude and Codex resume
with the same bypass policy as LFG's server-managed launch paths. Extended the
embedded desktop regression suite to assert every required flag.

**Result:** Confirmed. The two live manual-mode processes were both `lfgd-*`
Claude sessions running plain `claude --resume <id>`. The rebuilt desktop app's
82 embedded feature tests pass, including the new Claude and Codex assertions.
