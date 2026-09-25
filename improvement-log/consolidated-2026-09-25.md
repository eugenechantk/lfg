# Improvement Log Digest — 2026-09-25

**Logs processed:** 1 (`improvement-log-20260922-165449.md`)

**Date range:** 2026-09-22 to 2026-09-23

**Observations found:** 6 (6 unaddressed)

## Patterns

### Verify the cheapest boundary before expanding the diagnosis

- **Frequency:** 3 observations
- **Summary:** Path parsing, attachment presentation, and sibling edge cases were
  investigated through broader or slower routes before checking the narrowest
  observable boundary.
- **Current coverage:** The project workflow already requires runtime proof, but
  does not prescribe this diagnostic order.
- **Recommended fix:** For LFG file-display failures, verify file existence,
  server response, and the literal client request in that order. Use Files &
  Links before transcript scrolling when attachment resolution is the subject.
- **Mechanism:** Project debugging guideline or skill update during the next
  deliberate self-improvement pass.

### Preserve shared-tree work

- **Frequency:** 2 observations
- **Summary:** Deleting an unchecked file and stashing a concurrently edited
  tree both risked losing another session's work.
- **Current coverage:** AGENTS.md and the session-cleanup workflow already say to
  treat unfamiliar dirty work as user-owned and avoid whole-tree destructive
  operations.
- **Recommended fix:** No new rule. Follow the existing rule: inspect before
  deletion and use a temporary worktree instead of whole-tree stash operations.
- **Mechanism:** Existing AGENTS.md coverage.

## One-Off Observations

### Read FlowDeck subcommand help before guessing flags

- **Session:** 20260922-165449
- **Summary:** Four invocations failed because simulator flags and output options
  were guessed.
- **Worth persisting?** No. The current FlowDeck skill and simulator isolation
  hook already expose the correct command shape.

## Already Addressed

- Shared-tree preservation is covered by AGENTS.md and session-cleanup rules.
- FlowDeck command discovery is covered by the FlowDeck skill and CLI help.

## Recommended Actions

| # | Action | Mechanism | Location | Priority |
|---|---|---|---|---|
| 1 | Add the three-boundary file diagnostic order at the next workflow review | skill update | LFG debugging workflow | Medium |

## Logs to Archive

None. The source log remains until the recommended workflow improvement is
reviewed and explicitly approved.
