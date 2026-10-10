# Matching list toolbar actions

## User story

Sessions uses the same Search and More buttons as Tasks on iPhone and iPad.

## Success criteria

- [x] Search and More use matching native toolbar grouping, dimensions, symbols, and placement.
- [x] Sessions retains visible host status and all existing More actions.
- [x] Search opens the current list's bottom field, focuses it, and cancels cleanly.
- [x] List actions do not leak into session or task details; Back restores them.
- [x] Both phone and compact iPad sidebar fit without clipped or missing actions.

## Implementation

Replace the custom Sessions header circles with native primary-action toolbar
items, matching Tasks. Keep host status in the leading toolbar slot. Let the
system draw the navigation background and scroll edge effect. Keep existing
search state and menu callbacks.

The initial native status item collapsed to button width. Reserve space based on
the list width, after allowing for Search and More. Keep the host status background
plain so it stays readable without looking like another action.

When individual names cannot fit, show a count of connected hosts. The compact
status still exposes each host name and state to VoiceOver. Use ViewThatFits to
prefer full names whenever their natural width fits the toolbar slot.

Apple references:
- https://developer.apple.com/documentation/swiftui/viewthatfits
- https://developer.apple.com/design/human-interface-guidelines/toolbars

## Verification

This is a visual composition change with no new business logic. Build the app
and run an independent recorded iPhone and iPad audit. No implementation-shaped
unit tests are added. Retain screenshots comparing both lists and recordings
of Search, More, and navigation.

## Release boundary

No commit, production host restart, or TestFlight release is requested this turn.

## Results

FlowDeck build passed. The independent visual audit passed on iPhone 17 Pro and
iPad Pro 11-inch, both on 26.3. Search and More match Tasks in grouping, icons,
size, spacing, glass, and trailing placement. The phone group measures about
102 by 46 points; the iPad group measures about 103 by 46 points.

Search, More, menu contents, detail navigation, and Back passed. Narrow layouts
show a readable host count. Evidence: `.codex/evidence/matching-list-toolbar/audit/evidence.md`.
The test apps and capture sessions stopped. The isolated fixture stopped.
