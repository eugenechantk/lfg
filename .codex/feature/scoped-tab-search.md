# Contextual search in the native tab bar

## User story

Search sessions from Sessions, and scheduled tasks from Scheduled Tasks.
Use Apple's native search control beside the two main tabs.

## Flow

Select a main tab, tap Search, and enter a query. The search destination uses
that tab's content type and a matching placeholder. Each type has its own
query state. Cancel restores the originating tab and its navigation context.
When search starts from a list, that list returns unfiltered. Selecting a
result opens its normal session or task detail. New-session creation moves to
the top controls. Desktop keeps its existing search.

## Success criteria

- [x] One native tab/search surface, with no overlapping bottom search toolbar.
- [x] Sessions search finds sessions, including existing host-backed results.
- [x] Task search finds tasks and never issues session-search requests.
- [x] Switching origins changes scope and keeps the two queries independent.
- [x] Cancel, result navigation, task history, and plus actions remain usable.
- [x] iPhone and iPad both expose usable native search and readable results.

## Verification

Run existing session-search and scheduled-task model tests. The changed query
bindings and native search activation are UI state, so verify their complete
sequence with read-only fixture hosts and recorded native UI flows. Build both
clients because the task view is shared. Run the desktop feature harness.
An independent iOS visual auditor must pass the final phone and tablet builds.

## Implementation and risks

Keep session search backed by its existing store, ranking, and pagination.
Do not move UI navigation state into the core package solely to unit-test it.
The native Search tab remembers the most recent main tab as its scope.
Keyboard and tab transitions need runtime proof.

Apple sources checked in the preceding design review:
- https://developer.apple.com/design/human-interface-guidelines/search-fields
- https://developer.apple.com/videos/play/wwdc2025/323/?time=797
- https://developer.apple.com/documentation/swiftui/tabsearchactivation/searchtabselection

## Implementation notes

The Search tab owns the native searchable modifier. Applying it to the whole
TabView exposed another search field in the task page's navigation bar.
The Search tab uses one stable navigation stack for both scopes. Replacing the
stack when changing scopes caused iPhone search to move into the navigation bar.
The task view can use this outer stack or own its normal standalone stack.

The main session view keeps its split navigation. The Search tab holds separate
session and task queries. Normal lists receive empty queries. Selecting a
result transfers its selection or task path to the normal destination.
Before handing off an archived session, the store preserves its display record
and transcript source host. This prevents clearing search from losing the row.

Both native builds pass. The desktop harness passes 173 assertions. The focused
Swift run passes 31 tests: 14 search, six focus, seven scheduled-task, and four
transcript-routing checks. Independent phone and tablet audits both passed.

Final evidence:
- `.codex/evidence/scoped-tab-search/phone-audit/evidence.md`
- `.codex/evidence/scoped-tab-search/ipad-audit/evidence.md`

The final candidate built at 11:37:41 UTC on 2026-10-09. The audits used iPhone
17 Pro and iPad Pro 11-inch simulators running iOS/iPadOS 26.3. Phone evidence
includes both search scopes with the software keyboard shown and hidden.

No task or session was created or changed during the audit. The read-only
fixtures rejected automatic registration requests. Test apps, recorders, UI
streams, and fixture servers were stopped. Simulator.app was closed; the
preexisting root simulator was returned to its headless booted state. The Mac
was re-locked after password-free GUI verification. The installed desktop app
and production host service were not restarted. Changes remain uncommitted.

## Residual coverage limits

The earlier-iOS fallback compiles but was not run on an older simulator.
No physical-device build or release was installed in this turn.

## Native transition checks

The app originally restored the origin manually while iOS 26 also restored it.
The final implementation lets the native policy own that transition. The manual
fallback remains for earlier iOS versions.

The phone audit reproduced search moving to the top after changing scopes.
A stable navigation stack fixes this. Two repeated cycles now keep both search
fields in the native bottom surface, with the correct origin icon and results.

Two audit findings were retracted after checking the exact interaction. Cancel
correctly restores an existing detail when search started there. On iPad, the
automation's enclosing Search group overlapped another tab; tapping the actual
text field preserves session search. These were not product navigation failures.
