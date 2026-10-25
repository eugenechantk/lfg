# Linked session status audit

Result: PASS for the implementation. Deployment remains unverified by this audit.

## Independent evidence

- Six adversarial tests pass with 60 assertions. Evidence: independent.test.ts and independent-output.txt.
- Four existing suites independently pass: 120 tests and 279 assertions. Evidence: regression-output.txt.
- All sixteen busy combinations across nested and cyclic lineage preserve each session's own busy state. The linked count remains accurate and input rows remain unchanged.
- Inline subagents still promote their parent's busy state.
- The actual push tick keeps a completed parent idle while linked session counts change through 1, 0, 1, 2, 0. Inline count 1 still makes it busy, and inline completion releases it.
- The actual journal watch-refresh function was extracted from source and executed with mocked dependencies. New-watch and existing-watch branches retain only inline execution counts across 0, 1, 0, 2.
- The native model, session store, and desktop implementation have no separate runningChildSessionCount override. The linked count cannot independently change their busy state.

## Finding resolved

The initial two-file repair changed REST rows but left three hidden promotions. The journal folded linked counts into its inline count at both watch creation and refresh. The push tick also folded linked counts into its execution count. Those three sites now read only runningChildAgentCount. Independent behavior tests cover all three repairs.

## Limits

- No product source was edited by this audit.
- Push sends, journal dependencies, and live sessions were not mutated. Test effects use mocks.
- Frozen release hashes, usage endpoint preservation, sessions, schedules, and post-deployment live state require deployment verification.
