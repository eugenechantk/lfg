# Narrow desktop window

Let the desktop window shrink to 180 points. Keep the Tasks toolbar actions at the right, matching Sessions.

## Success criteria

- [x] Sessions and Tasks accept a 180-point window width, including task details. Verify with native resize measurements.
- [x] Tasks uses right-aligned actions at normal widths. Verify screenshots and control bounds against Sessions.
- [x] Narrow windows retain access to switching views, search, creation, and task options. Native overflow is acceptable where controls cannot fit. Verify actual interactions.
- [x] Widening restores the regular toolbar without lost navigation or search state. Verify native resizing and navigation.

## Decisions

macOS sizes windows in points. Treat the requested 180 pixels as 180 points.
The old 760-point minimum guaranteed a centered toolbar. The new minimum takes precedence; adapt or use native overflow when space is limited.
Preserve the concurrent fork-routing edits. The follow-up request authorized installing the verified build on both Pro and Air. No commit was requested.

## Verification Evidence

The isolated native app uses the real desktop views and a read-only local fixture. Its launch wrapper sets the fixture configuration before constructing the session store. It does not use production hosts.

- The final standalone candidate builds and passes all 180 desktop feature assertions. Its signature passes strict verification.
- Actual Accessibility resize measurements accept 180 points in Sessions, Tasks, and task details. The detail screenshot shows the instruction and session history at that width.
- At 900 points, the Tasks list has More, Search, and Plus on the right. Task details put their options at the right.
- At 180 points, native overflow exposes the view switcher and labeled actions. Search opens an inline field with focus. The Tasks More submenu remains enabled.
- Independent native macOS visual verification passed. The Tasks actions match Sessions within one point; search values survive resizing. Task creation opens and cancels, and task detail options remain available in overflow. See `auditor/evidence.md` for measurements and screenshots.

Evidence lives in `.codex/evidence/narrow-desktop-window/`. Build and assertion results are in `build-final.log` and `desktop-feature-tests.json`. Native screenshots include `v3-tasks-900.png`, `v3-detail-900.png`, and `v3-detail-180.png`. The final overflow state is in `v4-list-overflow-tree.json`.

## Implementation notes

Session titles wrap to two lines below 320 points. Secondary host and transport badges move into the row tooltip at that width.

macOS Tasks uses the same compact search behavior as Sessions. The search button reveals a field below the toolbar; wide windows show the field in the toolbar. The iOS layout is unchanged.

Task actions use automatic macOS toolbar placement. The native menu style keeps the More submenu functional in overflow. Search and create buttons have text labels so overflow items have names.

The existing window-fit diagnostic requires every toolbar item to remain visible. It reports overflow as not fitting; native resize and interaction evidence verify the new narrow-window behavior.


## Deployment

Installed and relaunched the verified signed build on Pro and Air. Both installed copies pass 180 desktop checks and match the audited binary. Previous app bundles are backed up on both hosts. See `.codex/evidence/narrow-desktop-window/deployment/release.md`.
