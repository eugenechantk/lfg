# Feature — "Mark as unread" + unread count badges (iOS client)

**Tier:** Product (shipping TestFlight app → full workflow: spec → tests → implementation → live simulator verification).

## Goal

1. A **Mark as unread** action in the session detail view's `…` (more actions) menu.
2. **Unread count badges** in the app: a red count bubble in the session list top bar,
   a count on the Unread section header, and the **app icon badge** set to the number of
   unread sessions.

## Existing mechanics (do not break)

Read-state today is purely derived (`ios/LFGCore/Sources/LFGCore/ReadState.swift`):

- `SessionStore.lastSeenMessageID: [String: String]` (persisted in `UserDefaults`,
  key `lfg.lastSeenMessageID`, mirrored into the local `LFGStore`).
- `SessionStore.group(for:)` returns `.unread` for a session that is idle **and**
  whose `last?.id != lastSeenMessageID[sid]` **and** is not currently focused.
- `markOpened(_:)` is called from `focus(_:)`, from the streamed-message path while
  focused, from `hydrateTranscriptFromStoreIfEmpty`, and **on every 3s poll for the
  focused session** (`SessionStore.swift:1411`).

That last one is the constraint that decides the design: any "mark unread" implemented
by *clearing* `lastSeenMessageID` would be immediately undone by the next poll while
the detail view is still on screen. So manual unread is an **explicit persisted flag**,
not a derived state.

## Design

### A. `ManualUnread` (new, in `LFGCore`, pure + tested)

A tiny pure type so the precedence rule is unit-testable without the app runtime:

```
public enum ManualUnread {
    /// Manual flags survive until the session is *re-opened*. Opening a session the
    /// user marked unread clears the flag (they are reading it again).
    public static func afterOpening(_ sessionID: String, flags: Set<String>) -> Set<String>

    /// Marking unread is a no-op for optimistic placeholder ids ("local-…") — they
    /// aren't real sessions yet.
    public static func canMarkUnread(_ sessionID: String) -> Bool
}
```

### B. `SessionStore` (additive; keep the diff tight — file is edited concurrently)

- New stored property `private var manualUnread: Set<String>`, loaded in `init` from
  `UserDefaults` key `lfg.manualUnread` (stored as `[String]`), persisted by a private
  `persistManualUnread()`.
- `func markUnread(_ id: String)` — guard `ManualUnread.canMarkUnread(id)`; insert into
  `manualUnread`; persist; if the session is currently focused, release focus
  (`focusedID = nil`) so the group flips to Unread immediately.
- `func markRead(_ id: String)` — remove the flag, and set `lastSeenMessageID[id]` to the
  session's newest known message id (same body as `markOpened`), persisting both. Used by
  the detail menu when the session is *already* unread (menu item toggles) — see D.
- `focus(_:)` — clear the flag for the id being opened via
  `ManualUnread.afterOpening(...)` **before** `markOpened(id)`.
- `markAllRead()` — also clear `manualUnread` entirely and persist.
- `group(for:)` — after the `.working` check and before the derived-unread check, return
  `.unread` when `manualUnread.contains(sid)`. Manual unread therefore does **not**
  override Needs-you / Paused / Working (those are more actionable), but does ignore the
  focused-session exclusion (the user explicitly asked for it to look unread).
- `var unreadCount: Int` — `filteredSessions.filter { group(for: $0) == .unread }.count`.
  Uses `filteredSessions` (not `sessions`) so the count matches what the list shows under
  the active user filter. Note: this is *not* host-filtered — the host filter is a list-view
  concern; document that in a comment.
- `func isManuallyUnread(_ id: String) -> Bool` — for the menu's toggle label.

### C. Badges (views)

1. **App icon badge** — new small helper (e.g. `AppBadge.set(_ count: Int)` wrapping
   `UNUserNotificationCenter.current().setBadgeCount(_:)`, iOS 16+ API, no completion
   handler misuse). Drive it from `RootView` with
   `.onChange(of: store.unreadCount, initial: true) { _, n in AppBadge.set(n) }`.
   Push notifications from the server never set `aps.badge` (verified: no `badge` key in
   `src/`), so the client owns the badge number outright.
2. **Top-bar count bubble** — in `StatusBadge` (`SessionListView.swift`), append a red
   capsule with the count when `store.unreadCount > 0`, in both the single-host and
   multi-host layouts. Small reusable view `UnreadCountBubble(count:)`:
   monospaced-digit caption2 semibold, white on `Color.red`, `Capsule()`, min width so
   single digits stay circular, `.accessibilityLabel("\(count) unread sessions")`,
   `.accessibilityIdentifier("unreadCountBubble")`.
3. **Unread section header** — the Unread status header currently shows only
   "Mark all read"; show `UnreadCountBubble(count: section.items.count)` before it.
4. **iPad sidebar subtitle** — `statusSubtitle` gains `· N unread` when `N > 0`
   (single-host branch and multi-host branch both).

### D. Detail-view menu item

In `SessionDetailView.toolbarMenu`, above the `Debug — tap to copy` section (so it sits
with the other session actions, after Rename/Fork/Move):

```
if store.isManuallyUnread(sid) {
    Button { store.markRead(sid) } label: { Label("Mark as read", systemImage: "envelope.open") }
} else {
    Button { markUnreadAndExit() } label: { Label("Mark as unread", systemImage: "envelope.badge") }
}
```

`markUnreadAndExit()` calls `store.markUnread(sid)`, fires a success haptic
(`UINotificationFeedbackGenerator`), and then **pops back to the list** by invoking a new
`onMarkedUnread: () -> Void = {}` callback on `SessionDetailView`, wired in `RootView`
to `self.selection = nil` (same mechanism as `onEnded`, separate closure so the intent
stays readable). Rationale: after "I'll come back to this later", leaving the user parked
in the transcript reads as if nothing happened; popping to the list makes the new unread
row and the count bubble immediately visible.

Hide the item for placeholder sessions (`sid.hasPrefix("local-")` / empty sid).

## Success criteria

- **SC1** `ManualUnread` unit tests: `afterOpening` clears only the opened id; `canMarkUnread`
  rejects `local-…` and empty ids. `swift test` green in `ios/LFGCore`.
- **SC2** Marking a session unread from the detail menu returns to the list and the session
  appears under the **Unread** section (verified in the simulator by tapping).
- **SC3** The marked session **stays** unread across: the 3s poll, leaving/returning to the
  list, and an app relaunch (persistence). It becomes read again when the session is
  re-opened (its `.task` → `focus`).
- **SC4** The top bar shows a red bubble with the unread session count; the Unread section
  header shows the same count; "Mark all read" clears both to zero and empties the section.
- **SC5** The app icon badge equals the unread session count (goes to 0 after Mark all read).
- **SC6** No regression to existing derived unread behavior (an idle session with a new
  message still surfaces as Unread; the open session isn't marked unread by its own stream).

## Constraints for the implementer

- `ios/project.yml` is the source of truth for the Xcode project; new files under
  `ios/LFG/` are picked up by the existing glob — run `cd ios && xcodegen generate` only if
  a target/config change is actually needed. New `LFGCore` sources need no project edit.
- **`SessionStore.swift`, `SessionDetailView.swift`, `Components.swift` are dirty with
  another agent's in-flight work.** Keep every edit minimal and additive; do not
  reformat, reorder, or "clean up" surrounding code, and do not revert or stage anything.
- Swift 6 strict concurrency; `SessionStore` is `@MainActor @Observable`. Non-UI logic goes
  in `LFGCore` with a test (house rule in `ios/CLAUDE.md`).
- Do not commit. Build with FlowDeck only if you have it; otherwise leave the build/live
  verification to the supervising session.
