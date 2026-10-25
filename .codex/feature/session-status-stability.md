# Stable session status and Codex default

## User story

Eugene needs Codex to default to GPT-6.1 Sol. A session must stay running through quiet work and become idle when its turn ends.

## Success criteria

- [x] SC1: New Codex model selections default to gpt-6.1-sol when available. Verify model catalog regressions and live catalog discovery.
- [x] SC2: A running Codex turn does not flip idle during tools, quiet waits, or bookkeeping writes. Verify lifecycle replay regressions across the shared state reader and journal.
- [x] SC3: Claude completion, interruption, and terminal failures close the turn promptly. Bookkeeping cannot revive a stopped turn. Verify regressions based on the paywall transcript.
- [x] SC4: REST snapshots, journal events, and push observations use consistent state. Verify consumer regressions and live read-only comparisons.

## Platform

Bun and TypeScript host. Client model defaults may also need adjustment.

## Decisions

Preserve existing unrelated edits. Do not commit or push. Use real turn evidence rather than add a display debounce that hides incorrect state.

## Verification evidence

- Initial regressions reproduced seven failures before the implementation. Evidence: session-status-stability/red.txt.
- The isolated runtime passed 256 host tests and 557 assertions, plus TypeScript validation. Both Macs verified the same 277 source files.
- Independent audit passed nine adversarial tests with 46 assertions and 123 existing regressions with 230 assertions. Its deployed Pro checks also passed. Evidence: session-status-stability/audit/REPORT.md.
- Swift validation passed 649 XCTest cases (one skipped) and 486 Swift Testing checks. Desktop built separately and passed 259 feature checks.
- Full host suite: 1,372 passed; two stale iOS source checks failed identically against HEAD. A Chrome extension timeout passed on isolated retry. Evidence: full-tests.txt, baseline-menu.txt, browser-recheck.txt in session-status-stability/.
- Pro live observation covered eight snapshots over 48.7 seconds. This Codex session stayed running, the child never acquired a terminal row, and the abandoned paywall stayed idle. No busy deltas appeared for the active fixture or the false child row. Evidence: session-status-stability/pro-live.json.

## Runtime status

The host fix is deployed on Pro and Air. Rollout preserved scheduled-task settings and existing session IDs. The source was built from the previously deployed frozen source and only this task's host edits; unrelated checkout changes were excluded. No commit or push occurred.

Mobile and desktop fallback defaults are updated and tested in source. Their installed app binaries were not replaced. Live host model discovery uses GPT-6.1 Sol on both Macs. Air now runs Codex 0.163.0, matching Pro.

## Findings and limits

- Codex held parent and subagent rollout files open in one process. Choosing whichever wrote last changed the process identity on each scan. The journal interpreted each disappearance as idle. Child rollouts are now excluded from all terminal-binding paths, and old managed bindings can repair themselves.
- Claude turn arbitration used the whole file mtime. Queue and artifact bookkeeping could refresh an abandoned prompt or make an older running row beat a Stop hook. Arbitration now uses the decisive record timestamp, with mtime reserved for old timestamp-less formats.
- Claude final replies and terminal API errors now close a turn even if Stop or turn_duration is missing. Delivered background notifications do not start turns.
- The existing inferred Claude timeout remains fifteen minutes. A genuinely silent longer Claude tool can still demote. Explicit Codex turns have no silence timeout.
- Air required a Codex CLI upgrade from 0.155.1 to 0.163.0 because the older CLI did not advertise GPT-6.1 Sol. The final Air check passed: healthy API, GPT-6.1 Sol available and default, and all 277 source files matched. Evidence: session-status-stability/air-live.txt.
