# Simpler list navigation

## User story

Group scheduled tasks like sessions. Reduce the mobile list controls to Search,
More, and a frequent-use create action near the bottom.

## Success criteria

- [x] Tasks appear in collapsible Pending and Completed groups, with counts.
- [x] Recurring, paused, future, and currently running tasks remain Pending.
- [x] Finished one-time and cancelled tasks appear in Completed.
- [x] The task list has no All/Upcoming segment or host picker.
- [x] Mobile has no repeated Scheduled Tasks heading above its named tab.
- [x] Mobile list headers show Search and More; other session actions live in More.
- [x] The compact Sessions/Tasks controls align left and the separate + aligns right.
- [x] The bottom + creates a session or task for the current tab.
- [x] Only root lists show bottom navigation; session and task details hide it.
- [x] Search remains scoped to the current list; both tabs work on iPhone and iPad.
- [x] Search focuses a bottom field in the current view, without a sheet.
- [x] Desktop has a centered Sessions / Tasks segment in the same window.
- [x] The segment remains visible at compact and wide desktop sizes.
- [x] Task history uses plain session rows without a grouped card or extra row insets.

## Decisions

Pending starts expanded; Completed starts collapsed. Searches expand matching
groups. Paused tasks remain pending because they can resume. A cancelled task
with a running execution stays pending until that execution ends.

Desktop uses a centered native Sessions / Tasks segment instead of mobile tabs.
The segment replaces the old task button and return-to-sessions button. Grouping,
directory filtering, and refresh remain in the session display menu so the
center control has space. Task history uses a plain list, with one layer of row
padding matching the home session rows.
The user specified compact Sessions and Tasks buttons on the left and a separate
+ button on the right. Search and More stay at the top of each list. Use a small
bar built from the app's native glass buttons; the + remains an action, rather
than pretending to be a third navigation tab. The existing TabView still owns
the two navigation stacks. Search opens and focuses a bottom field from the
header. iPhone uses the native SwiftUI search toolbar. iPad uses UISearchBar in
a bottom inset because SwiftUI places its search field in the navigation bar.
An adjacent Cancel button is explicit because UISearchBar suppresses its own
Cancel button on iPad. It stays available even when the search query is empty.
Cancel restores the list controls. Opening a result hides search and navigation;
Back restores the root list. iPad adds a Sessions back action for its split view.

The phone dock extends 16 points into the bottom safe area, leaving 20 points
below the glass on a phone with a 34-point home-indicator inset. List content
reserves only the dock's occupied height. Phones with smaller insets lower it
less. Search modifiers exist only while search is open, so detail views have
no residual search toolbar.

Task details and their sessions share one typed navigation path. Back from a
history or edit session restores its task instead of discarding that context.

Native measurements found the desktop segment shifts at 620 and 700 points.
The minimum window width is now 760 points, where the segment stays centered
through navigation and resizing. Wider windows retain the same centerline.

Apple's tab accessory API places accessories above full-size tabs, so it does
not provide the requested side-by-side layout:
https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:)

Native bottom search reference:
https://developer.apple.com/documentation/swiftui/view/searchtoolbarbehavior(_:)

iPad Cancel behavior reference:
https://developer.apple.com/documentation/uikit/uisearchbar/showscancelbutton

## Verification

- Backend: 17 tests passed; Swift task tests: 10 passed.
- Desktop feature checks: 173 passed. Window fit passed at 760, 900, and 1200 points.
- iPhone: independent recorded audit passed on the final-v2 candidate. The glass
  lower edge sits 20 points above the screen edge. The audited iPhone 26 search
  and dock code paths remain unchanged in final-v4.
- Desktop: independent final-v2 audit passed. The segment center delta is zero
  at the minimum width. History rows are 46 points, matching the home list.
- iPad: navigation, history, agent editing, and form reload passed. The final-v4
  audit passed empty and populated search cancellation on both tabs. Cancel
  restores the root dock, reopening focuses search, and the narrow sidebar
  shows the complete field and button without clipping. Hidden detail views
  omit the dock; Sessions Back restores the list and dock.

Evidence lives under `.codex/evidence/task-chat-editing/`. Agent editing is
tracked in `task-chat-editing.md`. No production release is part of this work.
