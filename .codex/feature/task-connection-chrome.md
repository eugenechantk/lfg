# Shared connection chrome for Tasks

Product change. Replace the active schedule count with the same connection header used by Sessions. Reuse each platform’s existing connection warning and its state, instead of task polling errors producing their own connection banner.

## Success criteria

- Sessions and Tasks share the header and warning components.
- The task header shows host connection state instead of an active count.
- iPhone detail hides the list header; iPad keeps it in the sidebar.
- Connected and reconnecting states do not show an outage banner.
- A sustained full outage shows one shared banner. Partial outages use the same behavior as Sessions.
- Recovery removes the warning and retains cached task rows.
- Task API and action errors still have feedback. Transport errors use the shared connection warning.

## Verification

Run existing connection presentation and host health tests. Build both clients. Audit iPhone and iPad online, outage, recovery, and list/detail placement using isolated local fixtures. Verify desktop native rendering. No new tests will mirror the shared component wiring.

Implemented using shared host status and warning components. Network failures use the existing host-state grace window. Non-network task API failures remain visible only for hosts confirmed connected. Failed task actions retain their own feedback.

Existing tests passed: 67 XCTest tests, three Swift Testing tests, and 173 desktop feature checks. Both clients built. Desktop captures at 760 points confirm compact host status, the centered picker, cached task rows, one warning during outage, and no warning after recovery.

The independent iPhone and iPad audit passed. It confirmed matching headers, the reconnect grace period, one warning during full outage, cached rows, recovery, API-only failure feedback, and detail/sidebar placement. A partial two-host outage was not exercised in the mobile UI; existing host-state tests cover that rule.

Report: `.codex/evidence/20261010-113110-ios-visual-audit/evidence.md`. Build, test, and desktop evidence: `.codex/evidence/task-connection-chrome/`. Source hashes match the verified candidates. All audit apps, simulators, and fixtures were stopped or removed. No commit, release, or production restart was performed.
