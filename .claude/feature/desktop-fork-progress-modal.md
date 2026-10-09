# Feature: desktop fork progress modal

## User Story

As Eugene, when I choose **Fork session** in the desktop app, I want a modal that says the
session is being forked, so I know the click worked during the seconds before the new
iTerm window opens.

## User Flow

1. Right-click a Claude Code or Codex row in the main window and choose **Fork session**.
2. A modal sheet appears at once: a spinner, "Forking session", and the source title. It says
   a new terminal window opens when the branch is ready.
3. On success the modal closes, and the fork's iTerm window opens (existing behavior).
4. On failure the modal changes to "Couldn't fork session" with the server's error and an
   OK button.
5. **Hide** (or Escape) closes the modal while the fork keeps running. The menu item still
   reads "Forking…". If that hidden fork fails, the existing "Can't open session" alert shows
   the error.

## Success Criteria

- [x] SC1: Choosing Fork session shows the modal at once, naming the source title — **Verify by:** real app against a stub host whose `/api/sessions/fork` waits 8 s; axdriver screenshot during the wait.
- [x] SC2: A successful fork closes the modal — **Verify by:** same run; stub returns ok; modal gone after the response.
- [x] SC3: A failed fork shows the error inside the modal with an OK button — **Verify by:** stub returns 502 with an error; axdriver screenshot shows the text; OK closes it.
- [x] SC4: Hide closes the modal and a later failure falls back to the alert — **Verify by:** `ForkModal.outcome` unit checks in `--desktop-feature-test`.
- [x] SC5: Existing desktop feature tests still pass — **Verify by:** `lfg --desktop-feature-test`.

## Platform & Stack

- **Platform:** macOS desktop app (`desktop/`), single-file SwiftUI, built by `desktop/build.sh`.
- **Tests:** `--desktop-feature-test` CLI entry point in the production source (no test target).

## Steps to Verify

1. `desktop/build.sh`
2. `desktop/build/lfg.app/Contents/MacOS/lfg --desktop-feature-test`
3. Start the stub host on a spare port; launch the app with `LFG_DESKTOP_CONFIG_DIR` pointed at a
   scratch `hosts.json` that lists only the stub. Right-click the stub row, Fork session,
   screenshot during the wait, after success, and after a forced failure.

## Decision Log

- **Sheet, not alert.** An alert cannot show a spinner and demands a button. A sheet is the
  macOS modal for work in progress.
- **Failure shows in the same sheet.** Dismissing a sheet and presenting an alert in the same
  update is a known SwiftUI presentation race on macOS. Switching the sheet to a failure state
  avoids it.
- **A Hide button.** The fork request may take up to 90 s, and the iTerm open can block on the
  first-run automation consent prompt. A modal with no way out would lock the window for that
  long. Hide keeps the fork running; the existing alert reports a later failure.
- **Built and ran a scratch copy, not `desktop/build`.** Another session is mid-way through a
  Scheduled Tasks window in the same file and build script. The scratch bundle used build.sh's
  exact file list and Developer ID signature, so the existing iTerm automation grant applied.
  Not installed to `/Applications`: that would ship the other session's unfinished work.
- **No separate auditor run.** Every criterion was exercised in the real app through the real
  menu item (AX press on "Fork session"), with screenshots and AX-tree reads. An auditor would
  repeat the same stub rig on a locked Mac.

## Verification Evidence

Run 2026-10-09 on the Pro. Rig: `.claude/evidence/desktop-fork-modal/stub-host.ts` (fork waits
8 s, then answers per a `mode` file) + `scenario.sh` (axdriver: `AXShowMenu` on the row, AXPress
"Fork session"). App launched with `LFG_DESKTOP_CONFIG_DIR` pointing at a stub-only hosts.json.

| SC | Action | Observed | Artifact |
|---|---|---|---|
| SC1 | Fork, read AX tree at +1.5 s | `AXSheet` with busy indicator, "Forking session", "FORKPROBE source conversation", "A new terminal window opens when the branch is ready." | `forking.png` |
| SC2 | Stub answers ok at +8 s | sheet gone at +11 s; new tmux client on `lfg-forkprobe` (iTerm attached, created at the reply second) | stub.log + `tmux list-clients` |
| SC3 | `mode=fail`, stub answers 502 | sheet reads "Couldn't fork session" / "Fork failed: FORKPROBE stub refused the fork"; pressing OK → no sheet | `failed-in-modal.png` |
| SC4 | Hide at +1.5 s, then ok / fail | after Hide: no sheet; menu item reads "Forking…", disabled. ok → no sheet, iTerm attached. fail → "Can't open session" alert with the error. Plus 5 `ForkModal.outcome` checks | `hidden-fork-failure-alert.png` |
| SC5 | `lfg --desktop-feature-test` | `{"ok":true,"tests":168}` | — |

## Bugs

_None yet._
