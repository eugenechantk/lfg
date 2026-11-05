# Step 1: trace result delivery

Diagnostic prototype. Keep all phone bridges and production configuration unchanged.

## Scope

Correlate a synthetic local operation with its enclosing result and agent continuation.
Use per-launch telemetry routed to a loopback collector. Store only allowlisted metadata.
Synthetic probes send no phone input and change no production configuration.
The user approved the separate read-only database diagnostics. Those queries found no retained rows for the historical failure day.

## Criteria

- Record local marker completion, JSON event arrival and transport telemetry with one probe identity.
- Distinguish API/stream errors, delayed tool return and continuation without outstanding local work.
- Require all four rounds plus a final result for a successful probe. A stopped process is incomplete.
- Compare inherited transport with SSE only if the baseline result justifies it.
- Retain the exact scope and uncertainty. Fast probes do not prove the intermittent defect is fixed.

## Verification

Check marker counts, event counts, telemetry activation and final completion.
Check global config hash before and after. Verify no phone or production actions occurred.
Only continue to bridge comparison after reconciling this step's result.

## Current result

- [x] Capture correlated local markers and outer lifecycle events.
- [x] Validate sixteen complete command-and-image rounds across the original four launches.
- [x] Complete the archived-image control: four additional successful command rounds.
- [x] Reproduce a pre-command transport failure in history forks.
- [x] Reject HTTP-only as a verified fix after its bounded history trial failed.
- [x] Expand original timing attribution to all five affected sessions.
- [x] Preserve global configuration and leave phones unchanged.
- [ ] Identify the exact historical low-level failure. Its diagnostic database rows have expired.
- [ ] Verify a repair against the original fault. No repair was deployed.

The transport repair remains open. The independent bridge comparison followed after reconciling these results.
See report.md and DATABASE-READ-SCOPE.md. No bridge replacement follows from these probes.
