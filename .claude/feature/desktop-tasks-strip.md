# Feature: the desktop Tasks page gets the Sessions host strip

## User Story

As Eugene, on the desktop app's Tasks page I want the same status bar the Sessions list has above its rows (host dots, how many are running, and the menu with the grouping and filtering options), so the two pages read the same way.

## Today

- Sessions: `S2DeskHostStrip` (board `dA2-sessions`): "● Pro ○ Air offline · 3 working" and a "By status ⌄" capsule whose menu holds Group by (status / directory) and "Hidden directories…".
- Tasks: a thin grey band from before S2: "● Pro ● Air" at 11pt with a hairline, "· N running", and a host-filter capsule only when there are two or more hosts.

## Success Criteria

- [x] SC1: At 400pt the Tasks page shows the same strip as Sessions: same dots, colours, type, "offline" treatment and capsule, "· N running" in place of "working". — **Verify by:** window shots of both pages; measure the strip's row and the capsule within 1pt.
- [ ] SC2: The capsule's menu on Tasks offers: Show tasks on (All hosts / each host), Group by (status / directory), Hidden directories…. — **Verify by:** code review plus a shot with the menu open is not possible off-screen, so a unit test of the menu model and a live click on the installed app.
- [ ] SC3: "By directory" groups tasks by their folder (basename of `cwd`), folders A–Z, each group foldable; "By status" is unchanged. — **Verify by:** LFGCore tests for the grouping; a window shot in directory mode.
- [x] SC4: Hidden directories hide tasks whose `cwd` is hidden, with the same rule the Sessions list uses. — **Verify by:** LFGCore test; a shot with a fixture dir hidden.
- [x] SC5: Sessions page unchanged (byte-identical window shot at 400pt). — **Verify by:** `cmp` of before/after `--board` shots.
- [x] SC6: iOS unaffected: LFGCore suites green; the iOS target builds. — **Verify by:** `swift test`; `flowdeck build`.

## Plan

1. `S2DeskHostStrip`: optional `workingLabel` and an optional extra menu section above Group by. Sessions call unchanged.
2. `shared/ScheduledTasksView.swift` (macOS branch): the strip becomes `S2DeskHostStrip`; a `groupMode` state; directory grouping; a `hidesDirectory` hook and `onHiddenDirectories` injected by `ScheduledTasksPane`.
3. `ScheduledTasksPane`: passes the desktop's hidden-dir rule and presents the hidden-directories popover.
4. Grouping and hiding logic in LFGCore (`TaskDirectoryGrouping`) with tests.

## Decision Log

- 2026-10-16 — The same control, not a new one, so no canvas round first; the `dA2` Tasks board on the canvas now differs from the app (its narrow band). Flag it for a canvas update.
- 2026-10-16 — Built in the S2 worktree, not root: a Codex session is mid-edit in `desktop/LFGSessions.swift` and `shared/ScheduledTasksView.swift` there and asked that nothing be rebuilt or installed until its audit ends. My hunks in the shared file are listed in the coordination note so its later commit can merge.
- 2026-10-16 — The host filter the old band had stays, as the first menu section ("Show tasks on").

## Verification Evidence

Evidence folder: `.claude/evidence/desktop-tasks-strip/` (window shots at 400pt, 1x: `baseline-*.png` before, `after-*.png` after).

| SC | Check | Result |
|---|---|---|
| SC1 | Pixel probe of the strip in `after-sessions.png` vs `after-tasks.png` | Identical: host dot x16–22 y60–66, label row y59–67, capsule x314–374 y59–68. "· N running" shows when a task runs (0 in the fixtures). At 700pt the toolbar no longer repeats the host status (`after-tasks-700.png`) |
| SC2 | Code: `desktopHostStrip` passes the host-filter Picker as `leadingMenu` (only with 2+ hosts), then Group by, then Hidden directories… | By construction; the menu cannot be opened in an off-screen shot. Live click: pending the install (see status) |
| SC3 | `TaskDirectoryGroupingTests`: folder name, A–Z grouping with order kept | 3 tests pass. Directory-mode shot: the harness has no switch for the tasks group mode; pending the live check |
| SC4 | `TaskDirectoryGroupingTests.hidden` with `HiddenDirs(["/Users/e/.gbrain"])` | Hides the task under it, keeps the other |
| SC5 | `cmp baseline-sessions.png after-sessions.png` | Byte-identical |
| SC6 | `swift test` in LFGCore; `flowdeck build` (iOS) | 644 XCTest + 424 Swift Testing pass; iOS build SUCCESS |

Live over the Pro's tasks (`after-tasks-live-pro.png`): the strip sits above the real status groups.

Status (2026-10-16): built and verified off-screen in the S2 worktree; **not installed** — a Codex session asked that nothing be rebuilt or installed on either Mac until its own audit of the Tasks page finishes. Install after that, then the live click on the menu (SC2, SC3 shot).

## Bugs

_None yet._
