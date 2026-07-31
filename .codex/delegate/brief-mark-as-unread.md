# Delegation Brief: iOS "Mark as unread" + unread count badges

**Goal:** Implement the full spec in `.claude/feature/mark-as-unread-and-unread-badges.md`
(read it first — it is the authoritative spec, written by the supervising Claude session,
including the design rationale and the trap that dictates the design).

Repo: `/Users/eugenechan/dev/personal/lfg` · target: the iOS client under `ios/`.

## Constraints

- **Read `ios/CLAUDE.md`** before editing — house conventions (non-UI logic goes in
  `LFGCore` with a test; `SessionStore` is the single source of truth; Swift 6 strict
  concurrency; `ios/project.yml` is the project source of truth, not the `.xcodeproj`).
- **`ios/LFG/SessionStore.swift`, `ios/LFG/SessionDetailView.swift`, and
  `ios/LFG/Components.swift` are dirty with ANOTHER agent's in-flight work.** Keep every
  edit minimal and strictly additive. Do NOT reformat, reorder, refactor or "tidy"
  surrounding code. Do NOT `git add`, `git stash`, `git checkout`, `git commit`, or revert
  anything. Do not touch `desktop/`.
- Do NOT commit or push.
- Do not run `xcodebuild`/`xcrun`/`simctl` directly (house rule: FlowDeck only, and the
  supervising session owns the simulator run). `swift test` inside `ios/LFGCore` is fine
  and expected.

## Spec

See the feature doc, sections A–D. Summary of what to build:

1. `ios/LFGCore/Sources/LFGCore/ManualUnread.swift` — pure helpers (`afterOpening`,
   `canMarkUnread`) + `ios/LFGCore/Tests/LFGCoreTests/ManualUnreadTests.swift`
   (XCTest, matching the style of the neighbouring `ReadStateTests.swift`).
2. `SessionStore`: persisted `manualUnread: Set<String>` (`UserDefaults` key
   `lfg.manualUnread`), `markUnread(_:)`, `markRead(_:)`, `isManuallyUnread(_:)`,
   `unreadCount`, flag-clearing in `focus(_:)` and `markAllRead()`, and the one extra
   branch in `group(for:)` (precedence exactly as specified: after `.working`, before the
   derived-unread check, and it bypasses the focused-session exclusion).
3. Badges: app icon badge driven from `RootView` via a small `AppBadge` helper wrapping
   `UNUserNotificationCenter.setBadgeCount`; reusable `UnreadCountBubble(count:)` view;
   wired into `StatusBadge` (both single- and multi-host layouts), the Unread section
   header, and the iPad `statusSubtitle`.
4. `SessionDetailView`: the toolbar-menu item (toggles label between "Mark as unread" and
   "Mark as read"), success haptic, and a new `onMarkedUnread` callback wired in
   `RootView` to clear `selection`.

## Verification (run these; report their output)

```
cd /Users/eugenechan/dev/personal/lfg/ios/LFGCore && swift test 2>&1 | tail -25
```

Also confirm the app target still type-checks as far as you can without building via
Xcode tooling (e.g. re-read your edits for Swift 6 concurrency correctness — `AppBadge`
must not violate `@MainActor` isolation, and `setBadgeCount` is the iOS 16+ async-throwing
API: call it in a `Task` and ignore/log the error rather than using a deprecated
`UIApplication.applicationIconBadgeNumber`).

## Definition of done

- [ ] `ManualUnread` + tests added; `swift test` green in `ios/LFGCore`.
- [ ] All of SC1–SC6 in the feature doc are implementable/true by inspection (the live
      simulator checks SC2–SC5 are the supervising session's job — do not attempt them).
- [ ] Diff touches only: new `LFGCore` files, new test file, and additive edits inside
      `ios/LFG/SessionStore.swift`, `SessionDetailView.swift`, `SessionListView.swift`,
      `RootView.swift`, plus (if needed) one new small file under `ios/LFG/` for
      `AppBadge`/`UnreadCountBubble`.
- [ ] No commits, no staging, no reverts, nothing under `desktop/` or `src/` touched.

## Report back

Files changed (with a one-line reason each), the `swift test` output tail, any place you
deviated from the spec and why, and anything you left incomplete.
