# iPad sidebar navigation

## User story

Keep the Sessions and Tasks tabs and the create button inside the iPad sidebar.

## Success criteria

- [x] In regular-width iPad layouts, the tabs and plus stay within the list sidebar.
- [x] Sessions and Tasks both use a sidebar and a separate detail pane.
- [x] Selecting a task shows its instructions and history in the detail pane.
- [x] A history session opens in that pane; Back restores the selected task.
- [x] The plus opens the correct creation flow; cancelling restores the sidebar.
- [x] Search replaces sidebar navigation while active and restores it on cancel.
- [x] Hiding the sidebar hides its controls; restoring it restores the controls.
- [x] iPhone layout and root-only dock behavior remain unchanged.

## Design

Move the dock into the list column's bottom inset. The sidebar remains a root
list when a detail is selected, so its navigation remains available. Give Tasks
the same split layout, using the existing task route and session destination.
Keep the existing phone navigation stack and dock placement.

## Verification

Build the iOS client. Independently record iPad Sessions, Tasks, detail, history,
Back, Search, and creation cancellation. Verify the controls remain within the
sidebar and the detail pane has no dock. Check the phone layout for regression.
No new scheduling or server behavior is part of this change.

## Release boundary

No commit, host restart, or TestFlight release is requested this turn.

## Verification results

The iOS build and standalone desktop compile passed. The desktop feature runner
passed all 173 checks using the app bundle resources.

The independent iPad audit passed both 320-point sidebars. Tabs fit from x26 to
x202; plus is centered at x290, within sidebar bounds x10 to x330. Neither detail
pane has a dock. Search, both creation cancellations, sidebar hiding, task
selection, history navigation, and Back passed. The phone regression passed:
Sessions and Tasks retain the original full-width root dock; task and session
details hide it, and Back restores it.

Evidence: `.codex/evidence/ipad-sidebar-navigation/audit/evidence.md`.
All owned audit apps, recordings, capture sessions, and the fixture stopped.
The iPad was shut down; the phone retained its original booted state.
