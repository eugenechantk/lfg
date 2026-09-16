# Improvement Log — Session 0167JUdGTHxzYBZBuupfv7Mf

## Tracker

## Log
- [ ] 2026-09-06 — Lost a tool call to a `cd` persisting between Bash calls

### 2026-09-06 — Lost a tool call to a `cd` persisting between Bash calls

**What happened:** Ran `cd ios/LFGCore && swift test` in one Bash call, then a later `grep ios/LFG ...` failed with "No such file or directory" because the shell was still in `ios/LFGCore`.
**Why this was wrong:** The Bash tool documents that the working directory persists across calls. Costs a round trip every time and can silently target the wrong tree for a write.
**What better looks like:** Prefix every Bash call with an absolute `cd /Users/eugenechan/dev/personal/lfg &&`, or use absolute paths, instead of relying on where the last call left the shell.
