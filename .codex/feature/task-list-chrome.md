# Scheduled task navigation controls

## User story

Browse scheduled tasks across all hosts with only an All and Upcoming toggle.
Open a task without the bottom tab and search controls covering the detail.

## Success criteria

- [x] The task list has no host filter on iOS or desktop.
- [x] All and Upcoming remain usable across hosts.
- [x] Opening a task from the list or search hides the mobile tab and search bar.
- [x] Back restores the list controls; repeated navigation and session history work.
- [x] The navigation works on iPhone and iPad.

## Implementation

Remove the host selection state and predicate from the shared task list.
Keep host labels in task rows and host selection during task creation.
Use native destination-level tab-bar visibility for mobile task details.

## Verification

This product change removes a control and changes native toolbar visibility.
No new unit tests are needed for these presentation modifiers. Build both clients
and use recorded simulator flows with read-only fixture hosts. An independent
visual auditor will check direct entry, search entry, Back, and history navigation
on iPhone and iPad. Use the desktop feature harness for the shared-view change.

## Release boundary

Make and verify the change. Do not commit or upload another TestFlight build
unless requested. The prior build remains available.

## Results

The iOS FlowDeck build and desktop build passed. The desktop harness passed
all 173 assertions. Independent iPhone 17 Pro, iPad Pro 11-inch, and desktop
UI audits passed. Recordings prove direct entry, search entry, Back restoration,
repeated navigation, and history handoff. The task list aggregates hosts;
Upcoming excludes the completed fixture task.

Reports:
- `.codex/evidence/task-list-chrome/phone-audit/evidence.md`
- `.codex/evidence/task-list-chrome/ipad-audit/evidence.md`
- `.codex/evidence/task-list-chrome/mac-audit/evidence.md`

The iPad retained existing host preferences and showed extra read-only host
rows alongside the controlled fixtures. No task action or session prompt ran.
No older iOS simulator or physical device was checked in this turn.
