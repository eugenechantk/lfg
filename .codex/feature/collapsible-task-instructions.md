# Collapsible task instructions

The task detail initially shows up to three lines of instructions in secondary text.
Long instructions offer Show more and Show less. Short instructions need no extra control.
The expanded instructions remain read-only and selectable. Each task starts collapsed.

## Verification

- [x] Build the shared view for iOS and macOS.
- [x] Verify long text collapses to three lines and expands completely.
- [x] Verify short text has no disclosure control.
- [x] Verify secondary text styling and the session history below it.
- [x] Verify a different task starts collapsed.

This is local UI state and layout, so verify actual rendering and taps instead of adding tests that mirror a Boolean.
Use read-only fixtures. No release, commit, or production data changes are needed.

Both native builds passed. Independent phone and iPad captures verify the toggle, read-only selection, short text, and task reset. Desktop snapshots verify collapsed, expanded, and short states. The desktop expanded snapshot seeds its initial state; actual taps were verified on iPhone and iPad.

Evidence: `.codex/evidence/collapsible-task-instructions/audit/evidence.md`.
