# Feature: desktop-cmd-k-search

## User Story

As Eugene using the lfg Mac app, I want Command-K to open session search with the cursor already in the field, so I can find a session by typing at once, without reaching for the mouse.

## User Flow

1. The lfg window is in front (Sessions or Tasks showing, search row open or closed).
2. Eugene presses Command-K.
3. The window shows Sessions, the search row is open, and the search field has keyboard focus.
4. Eugene types; the list filters as usual.

## Success Criteria

- [x] SC1: Command-K with the search row closed opens it and focuses the field, so typed keys land in it — **Verify by:** live app: press ⌘K via System Events, type a query, read the field value back through the accessibility tree.
- [x] SC2: Command-K with the search row already open never closes it; it refocuses the field (focus moved elsewhere first) — **Verify by:** live app: open search, move focus off the field, press ⌘K, type, read the value.
- [x] SC3: Command-K while Tasks is showing switches to Sessions and opens the focused search row — **Verify by:** live app: switch to Tasks, press ⌘K, check Sessions shows and typed text lands in the session field.
- [x] SC4: The command is in the menu bar (Edit ▸ Search Sessions ⌘K), so it is discoverable — **Verify by:** read the Edit menu items through System Events.
- [x] SC5: Existing desktop feature tests still pass — **Verify by:** the app's built-in test CLI.

## Platform & Stack

- **Platform:** macOS desktop app (`desktop/`), built by `desktop/build.sh` with `swiftc`, no Xcode project.
- **Language:** Swift 6 / SwiftUI, macOS 26.
- **Key frameworks:** SwiftUI `Commands`, `FocusedValues`, `@FocusState`.

## Steps to Verify

1. `LFG_DESKTOP_OPTIMIZATION=-Onone desktop/build.sh` (or the default build).
2. Run the built-in test CLI.
3. Launch the built app from `desktop/build/lfg.app`, then drive ⌘K and typing through System Events, reading state through the AX tree.

## Implementation Phases

### Phase 1: Command + focused action

- Scope: a `FocusedValues` entry the window publishes; an Edit-menu `Commands` group with ⌘K that calls it; `ContentView` action that shows Sessions, reveals the row and focuses the field.
- Success criteria covered: SC1–SC5.
- Verification gate: build, test CLI, live ⌘K probes.

## Decision Log

- **⌘K always means session search, even from Tasks.** It switches to Sessions rather than opening task search. Session search is the app's global search (every session on every host), and "jump to a session" is the usual meaning of ⌘K (Slack, Linear). The Tasks page stack is kept, so switching back returns to where Eugene was.
- **⌘K only opens, never toggles closed.** The request is "open and focus so I can search at once"; a toggle would hide the field on a second press when focus had wandered.
- **Menu placement: Edit menu, after the text-editing group (beside Find).** That is where Mac apps keep search commands, and a menu item makes the shortcut discoverable.
- **No independent auditor run.** The live evidence below reads state back from the real app with real keystrokes, and a second run would unlock and drive Eugene's Mac again for a one-command change. Offered instead of run.
- **Search button tooltip now says "Search sessions (⌘K)"**, so the shortcut is visible where people already look.
- **Mechanism: `focusedSceneValue` + `@FocusedValue` in `Commands`**, the SwiftUI-native way for a menu command to act on a window, instead of NotificationCenter. The value is nil while the creation sheet is up, so ⌘K cannot change the list under a sheet.

## Verification Evidence

Build: a scratch copy of the dirty tree (`desktop/build.sh`), so `desktop/build/lfg.app` was not touched. Live runs used real System Events keystrokes; axdriver's per-process typing does not reach SwiftUI text fields (it typed nothing even into a focused field), so it was used only to read state.

Screenshots stay local and untracked (`.claude/feature/evidence-desktop-cmd-k/`): they show real session titles, including a customer email.

| Criterion | Action | Observed | Artifact |
|---|---|---|---|
| SC5 | `lfg --desktop-feature-test` | `{"ok":true,"tests":259}` | — |
| SC4 | read Edit menu via AX | `Search Sessions`, CmdChar `K`, modifiers 0 (⌘ only). Disabled with no window, enabled when the window is key, disabled while the New session sheet is up, enabled after Escape | `evidence-desktop-cmd-k/07-sheet-open.png` |
| SC1 | close row via the toggle → ⌘K → type `alpha` | no text field → field focused, value `''` → value `alpha` | `evidence-desktop-cmd-k/03-sc1-cmdk-closed-row.png` |
| SC2 | Return (unfocuses, row stays) → ⌘K → type `beta`; then ⌘K again | focused=False → focused=True → value `beta` (old query selected and replaced); second ⌘K: row still open, focused | `evidence-desktop-cmd-k/04-sc2-refocus.png` |
| SC3 | press `destination_tasks` → ⌘K → type `gamma` | Tasks showing, no field → Tasks gone, `Search sessions` field focused → value `gamma`, "Searching every session…" | `evidence-desktop-cmd-k/05-sc3-tasks-before.png`, `06-sc3-after-cmdk-from-tasks.png` |


## Bugs

_None yet._
