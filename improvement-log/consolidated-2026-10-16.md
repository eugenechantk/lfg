# Improvement digest: 16 October 2026

Reviewed three new logs. Two are empty templates. The substantive log contains twelve tracker items. Original logs remain intact.

## Patterns

- Compare builds using the same saved client state. Reset or record event cursors before blaming a UI change.
- Verify the actual release and both hosts. Upload success, a local commit, and Syncthing activity do not prove deployment.
- Run the complete user flow before shipping. Cover replay, resync, and live stream branches.
- Read tool and configuration boundaries first. Use literal simulator IDs, exact UI targets, and the desktop configuration directory.

## Addressed

The event resync fix and closed-list performance fixes are already committed. Existing project instructions cover frozen deploy trees, host source hashes, port-specific restarts, and simulator targeting.

## Recommendations

1. Isolate the two real-corpus resumable tests or give them an explicit timeout.
2. Add stream contract coverage for every connection branch.
3. Consider generating the desktop compiler source list after checking platform compatibility.
4. Document the desktop configuration directory in the project guide.

These are proposals, not changes made during this release. No global instructions, skills, or memories were changed. No logs were deleted.
