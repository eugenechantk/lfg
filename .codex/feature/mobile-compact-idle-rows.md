# Compact idle and closed rows

Product tier. iPhone session list.

## User story

Idle and closed sessions keep the same row height as running sessions. Their title and metadata sit close together and vertically centered.

## Success criteria

- [x] Idle and closed rows contain two adjacent visible lines, with no blank status slot. Verify screenshots and measured text positions.
- [x] The two-line group is vertically centered. The status dot aligns with its title. Verify screenshot geometry.
- [x] Idle, closed, and working rows retain the same height. Working and other meaningful status lines remain visible. Verify row frames and running status.
- [x] Relevant existing tests, simulator build, and independent visual audit pass.

## Implementation

Omit the status view for idle and closed groups. Center the remaining stack within the existing 64-point content area. Move the dot with the title. Keep outer padding and row tap targets.

## Verification plan

Use the existing network-free SessionListTimeFixture with running, idle, and closed states. Check light and dark appearance on iPhone 17 Pro. No adaptive toolbar changes are involved.

Run the existing SessionListRow tests. This is a layout-only change; new logic tests would duplicate the view structure.

## Evidence

- Existing SessionListRow tests: 18 passed in four suites. Log: `.codex/evidence/20261016-compact-idle-rows/tests.log`.
- Final FlowDeck build and launch passed on iPhone 17 Pro / iOS 26.3. Log: `build-run-final.log` in the evidence directory.
- Self-check: two-line idle/closed stacks render adjacent text. Full working and idle row spans measure 87 points in the network-free fixture. Visible clusters sit within one point of their row center. The fixed content frame preserves the closed row height too.
- `final-light.jpg`, `final-light-tree.json`, and `self-geometry.json` record the static result. Fixture rows have distinct accessibility IDs.
- Independent visual audit: PASS on iPhone 17 Pro in light and dark appearance. Report: `.codex/evidence/20261016-211817-ios-visual-audit/evidence.md`. The repeated section pitches match at 101.67 points, confirming equal row heights. All visible clusters share the same vertical center, and no text is clipped.

## Residual risks

Simulator layout verification is complete. Physical phone rendering was not tested. Release status is tracked separately from this feature audit.
