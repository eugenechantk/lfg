# Desktop task creation inside the window

## User story
Create a task using the approved Tasks redesign form, inside the app window. The current desktop creation paths open modal sheets.

## Reference
The exported Tasks redesign boards are in `.claude/tasks-a2/design/`. Rendered `dA2-edit.dc.html` in Chrome and inspected it on 2026-10-16. The Once board is `dA2-edit-once.dc.html`; the other `dA2-edit-*` boards specify repeat variants. Mobile `tA2d-edit*` boards establish shared controls.

## Flow
1. More > New scheduled task opens the designed form in the existing window.
2. Set Name, Instructions, Once or Repeat, timing, host, folder, agent, and model.
3. Cancel returns to the list without saving. Save persists the task and refreshes the list.
4. More > Create with chat opens an in-window setup page, then opens the conversation in iTerm.
5. Existing task edits keep using the same in-window editor.

## Success criteria
- [x] Creation and editing use the app container, with Cancel and Save in its title bar. Verify the live AX tree has no sheet and capture navigation.
- [x] Form components match the exported desktop boards at 400 points: name/instructions card, Once/Repeat schedule, Runs on, and toolbar. Verify independent component comparison for Once, Repeat weekdays, and finite repeat.
- [x] Cancel saves nothing; valid Save writes expected fields and returns to the list. Verify through a disposable fixture host with scheduling disabled.
- [x] Chat creation remains reachable, uses an in-window page, and retains errors and input while starting. Verify the route and a failed fixture response.
- [x] Desktop build and feature checks pass. No mobile presentation change. Verify the build, existing tests, and conditional scope.
- [x] Verified app is installed on Pro and Air; final binary hashes match.

## Decisions
Reuse the existing A2 editor, rather than duplicate its controls. Add desktop-only create routes to the existing task navigation stack. Keep iOS entry points and modal presentation unchanged.
The user was asked which creation route should be primary. Pending a reply, use the designed form as primary, with chat as a separate More action.
The reference uses an existing task. Creation has an empty draft and the title New task; these are expected data differences.

## Verification evidence
- Signed standalone build passed; 183 built-in desktop checks passed.
- Live isolated app used only fixture host18932. New scheduled task opened in the existing window, with no AXSheet around the main form.
- Entered name/instructions, chose a folder, and saved. The list refreshed with the new row. saved-task.json confirms the fields and Once schedule.
- Native capture and tree: create-once-live.png, create-once-tree.json.
- The fixture starts no scheduler ticks or providers. Its chat route returns503 for retained-input testing.
- Independent artifact comparison is in progress.

## Tooling
The saved FlowDeck project is the iOS app. The desktop target is standalone Swift, built with desktop/build.sh. A raw open command was blocked by the Apple tooling hook; the built executable and CUA app binding provided the supported standalone test path. Tests use an isolated LFG_DESKTOP_CONFIG_DIR.
The first fixture config used an array instead of the required hosts object. It was corrected before any save. No real tasks were written.
A separate release session was asked to reinstall latest root while verification ran. It installed candidate8248fb7 on both Macs. It also stopped the first isolated test process; the replacement process remained isolated. Final installed hashes must still be verified after the audit.

## Audit completion
Independent visual audit passed at 18:50 HKT. The current desktop and shared source hashes match the audited candidate. The auditor verified Once, Weekdays, finite Repeat, inline creation, Cancel, Save, and retained chat input after an error. Report: `.codex/evidence/desktop-task-create-inline-20261016/audit/evidence.md`. Both-Mac installation will be recorded by the release session.

## Release installation
The release from commit `14dc192` is installed on Pro and Air. Both signed app binaries have SHA-256 `cb9f895e8f74631f8ee5a9955b0fa2292a2ddf354ff6e4ba1791312a53be74b3`. Both installed apps pass all 183 checks and reach both production hosts. Evidence: `.codex/evidence/all-hosts-release-202610162041/`.
