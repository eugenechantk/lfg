# Improvement Log Digest — 2026-08-19

**Logs processed:** 9 files (4 substantive, 5 empty templates)
**Date range:** 2026-08-17 → 2026-08-18

## Patterns

### 1. Verify the real UI state and interaction preconditions before diagnosing

- **Frequency:** 4 observations across the desktop-client, new-session, and transcript-performance sessions.
- **Summary:** Work was initially guided by the wrong client, an unverified directory change, a swipe that did not scroll, or screenshots that could not distinguish a no-op from runaway paging.
- **Existing coverage:** The project already records ground-truth-first diagnosis and FlowDeck interaction verification rules.
- **Recommendation:** No new standing rule. Continue requiring a visible state transition or instrumentation before treating a UI action as evidence.

### 2. Preserve evidence before restarting or replacing a failing process

- **Frequency:** 2 observations: restarting the desktop app destroyed its divergent in-memory state, and failed Codex creation killed the only pane containing its startup error.
- **Recommendation:** Add product-level diagnostic capture: a desktop state dump and server-side `capture-pane` logging before a failed Codex create tears down its pane.
- **Mechanism:** Product backlog; do not expand this release to implement it.

### 3. Verification artifacts must follow the run, never predict it

- **Frequency:** 2 observations: pre-filled feature evidence and a screenshot whose required precondition had not occurred.
- **Existing coverage:** The software-development and FlowDeck workflows already prohibit fabricated evidence and require action-by-action verification.
- **Recommendation:** No new rule; the failures were caught before delivery.

## High-value one-offs

- Live Codex SQLite databases were being synchronized between hosts, corrupting both. The databases were moved aside and Syncthing ignore rules were added and verified outside this repository.
- Promptless Codex create requests cannot discover a rollout ID because Codex writes the rollout at the first turn; verification must mirror the client and include a prompt.
- Cross-host rollout synchronization can make fallback session-ID matching bind another host's rollout. This remains a hypothesis requiring a dedicated reproduction.
- Long-transcript rendering had already been diagnosed but the deferred pagination fix had no durable backlog entry. The bounded transcript window is included in this release.

## Already addressed in this release

- New-session model defaults are inferred per directory and verified.
- Long-session transcript rendering is bounded and pages backward, with profiling evidence.
- The native session options menu keeps stable presentation state while transcripts stream.
- LFG server restarts explicitly restore Homebrew paths and warn when `tmux` is unavailable.

## Recommended follow-ups

| # | Action | Mechanism | Priority |
|---|--------|-----------|----------|
| 1 | Capture desktop filtering/session-count state before relaunch | Product backlog | Medium |
| 2 | Log the dying Codex pane before create-failure teardown | Product backlog | High |
| 3 | Reproduce cross-host Codex fallback-ID collision with host-tagged fixtures | Diagnosis/test task | High |

## Retention

The nine source logs remain in place. They were not deleted because consolidation requires explicit approval before removing source records; this release only records the digest.
