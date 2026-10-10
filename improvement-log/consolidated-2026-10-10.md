# Improvement Log Digest — 2026-10-10

This incremental digest covers the five new logs after the October 9 digest.
Two contain four observations. Three are empty session records. All remain intact.

## Findings

- A design canvas depends on its runtime. The global standalone HTML publishing rule needs a separate canvas policy.
- Recent native screenshots helped recreate the interface. A release-owned screenshot index could make those captures easier to find.
- A failed terminal bootstrap lacked a timestamped diagnostic. The updated connection script now records each failure and retries SSH exit 255 once.
- Pulling into the shared dirty tree failed safely. Project instructions already require preserving other sessions' files.

## Follow-up

Review the canvas policy and screenshot index separately. Existing release evidence already provides dated captures.
The connection diagnostics are implemented. Keep the shared-tree preservation rule; do not reset or stash other sessions' work.

No global instructions, skills, or memories changed. No logs were deleted.

## Source logs

- improvement-log-20261009-151728.md — empty.
- improvement-log-20261009-151909.md — canvas publishing and screenshot reuse.
- improvement-log-20261009-153732.md — empty.
- improvement-log-20261010-084353.md — empty.
- improvement-log-20261010-084410.md — connection diagnostics and shared-tree pulls.
