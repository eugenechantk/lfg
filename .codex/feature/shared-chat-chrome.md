# Shared session and chat chrome

Product tier. Reuse the shipped session controls for durable chats on iPhone and iPad.

## Success criteria

- [x] SC1: Session and chat lists use one native toolbar layout, host header, Search glyph and More glyph. Actions retain their own feature context.
- [x] SC2: Switching among Sessions, Tasks and Message preserves tab widths, dock insets and the plus button's position. Plus opens the selected feature's creation screen.
- [x] SC3: Chats use the same iPad split-view sidebar and native conversation toolbar as sessions. The transcript remains on an open canvas.
- [x] SC4: Search, More, creation, chat selection, settings, Back and sidebar toggling work. Offline creation and queued messages remain available.
- [x] SC5: Existing session navigation and native Mac compilation remain valid.
- [x] SC6: iOS appearance stays consistent between Sessions and Chats, in light and dark mode.

## Refactor guard and verification

This extracts UI controls and replaces chat-specific placement. It does not change storage, transport, model execution or queue ownership. Existing ChatAvailability, ChatWorkspace, ChatSessions, SessionStatusLine and navigation suites characterize that behavior. Run the package suite after the change. Do not add tests that merely read source or duplicate layout constants.

Native recordings and screenshots must prove placement and interaction on an owned iPhone 17 Pro and iPad simulator, in both iPad orientations. The independent iOS visual auditor is the final gate. Inspect the combined native build as well as the shared-source Mac build.

## Scope and ownership

Edit RootView, SessionListView, SessionDetailView, shared ChatSessionsView and a small iOS chrome component. Preserve the unrelated improvement-log edit. No commit, push, deployment or release requested in this turn.

## Findings

RootView already owns the dock. Its Message-specific cell width and side insets cause drift. Chats separately builds a phone header and an iPad HStack/card, and duplicates the bottom safe-area attachment. Sessions uses native navigation toolbar items and listScrollChrome.

## Implementation

`ConversationChrome.swift` supplies ListHeaderToolbar, ListOptionsLabel, ListCreateButton, ConversationToolbar and SidebarToggleToolbar. Sessions and Chats use these controls. The existing SessionTitleBarContent also renders chat titles and status with feature-specific accessibility identifiers. RootView remains the one owner of the tab dock; its Message-specific cell widths, ink and side insets are removed.

Chat lists use listScrollChrome and the same host connection header supplied by RootView. iPad chat navigation uses NavigationSplitView with the same sidebar width range and visibility binding as Sessions. Chat transcripts keep their open canvas. Chats inherits the iOS appearance; semantic colors keep content legible. The Mac retains its existing appearance.

## Verification results

- Swift package: 584 tests in 90 suites pass.
- iOS app: native simulator build and launch pass.
- Diff whitespace checks pass.
- The first native compile exposed two references to a file-private color token; the shared controls now use the equivalent system label color.
- The initial Mac check project omitted AlertStatus.swift added to the canonical desktop build since the October release. Regenerated its source list from desktop/build.sh; the Mac build passes. Subsequent source changes are confined to iOS-only labels and selection styling.
- Independent native visual audit PASS on the final build. Evidence: `.codex/evidence/shared-chat-chrome-audit/evidence.md`. Verified iPhone and both iPad orientations, light/dark appearance, exact control frames, plus routing, menus, search, settings, Back, sidebar toggles and offline queuing. No live model requests or production mutations.


## Residual risks

The independent audit covers the changed navigation and adaptive chrome with recordings and measured accessibility frames. Verification used simulator fixtures; physical devices and production connectivity were outside scope.

## Audit corrections

- Added explicit More-menu accessibility labels to retain spoken names as well as stable control identifiers.
- The independent audit found that selected iPad chat rows kept a dark fill in light appearance. The chat and session rows now share S2.listSelection, the existing session tint. Final iOS rebuild and independent re-audit pass for the corrected row and final binaries.

## Final state

Product sources match the audited final hashes. The canonical Xcode project is regenerated; the temporary review scheme and spec are preserved beside the local evidence. Both capture sessions and the owned fixture server are stopped. The saved FlowDeck configuration is unchanged. Changes remain local and uncommitted; no release was requested.
