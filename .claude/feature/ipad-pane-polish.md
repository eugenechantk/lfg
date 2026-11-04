# Feature: iPad file pane polish (2026-11-03)

## User Story

As Eugene reviewing the shipped iPad file pane, I want less chrome on three states, so that the pane and lists read cleanly.

## User Flow

1. Open a file in the pane on iPad landscape and expand it to full width. The top-left button is a plain back button. Tap it to return to the split.
2. With a file open, look at its card in the transcript. It looks like every other card.
3. Select a session in the Sessions sidebar, or a task in the Tasks sidebar. The row shows its fill and no border.

## Success Criteria

- [x] SC1: In full width, the top-left control is a circle back button (chevron only). There is no session name or status dot. Tapping it returns to the split. — **Verify by:** iPad sim screenshot of full width; tap `filePaneReturnToTranscript` and screenshot the split; `FilePaneUITests` still passes.
- [x] SC2: The transcript card of the open file has no blue fill, border or "Open" label. — **Verify by:** iPad sim screenshot with a file open in the pane.
- [x] SC3: The selected row in the iPad Sessions and Tasks sidebars shows only its fill, with no border, while a hardware keyboard is connected (the sim default). — **Verify by:** iPad sim screenshots of both sidebars with a selection.
- [x] SC4: No regressions. — **Verify by:** app build; `swift test` in `ios/LFGCore`; the FilePane app and UI tests.

## Platform & Stack

- **Platform:** iOS / iPadOS (SwiftUI). `shared/ScheduledTasksView.swift` also builds into the Mac app; the change there is iOS-only.

## Decision Log

- Worktree based on the Pro's local `main` (2daa01e), not `origin/main`: the Pro holds 10 unpushed commits, and the Air's own checkout is stale.
- The sidebar "border" is the iPadOS keyboard focus ring (`UIFocusHaloEffect`) on the focused List cell (square, outside the rounded pill), not a border the app draws.
  - Attempt 1: `.focusEffectDisabled()` on the List. Ring still drawn (shots 08–09).
  - Attempt 2: `.focusEffectDisabled()` on each row. Ring still drawn (shots 12–14). Researched after two misses: Apple's documented UIKit fix is `cell.focusEffect = nil` (WWDC21 "Focus on iPad keyboard navigation"); SwiftUI has no modifier that reaches List cells.
  - Attempt 3 (kept): `hidesCellFocusRing()` in `SessionListView.swift` — a zero-size, non-interactive UIView behind each row that finds its `UICollectionViewCell` and sets `focusEffect = nil`. The cell stays focusable, so the arrow keys still move the selection; only the ring goes (shots 15–17).
- Tasks sidebar: the same helper is applied, but the ring could NOT be reproduced there even without it (tap, Tab, arrows; shots b2–b9). Its rows are Buttons in a List without selection. Kept as a one-line precaution; flagged to Eugene.
- Built and verified on the Pro (Xcode 26.3, the release toolchain). The Air's Xcode 27.2 fails to type-check `TaskEditorViews.swift:558` (`TaskFlowLayout.sizeThatFits`), which this change does not touch — a latent break for the next Xcode.
- A private copy of the pane fixture (`~/.lfg/pane-fixture-34546475/fixture.ts` on the Pro) adds two tasks; the shared original under `.codex/feature/ipad-file-pane/` is untouched.
- Removed the now-unused `openFilePaneID` environment key and the pane's `sessionTitle` / `sessionIsBusy` inputs instead of leaving dead code.
- The media strip's marker for the current image/video stays: it is a pager position inside the pane, not a list item's selected state.

## Verification Evidence

Implementer runs, iPad Pro 11-inch sim `cc-34546475-ipad` on the Pro, dark, fixture sessions. Shots in `.claude/feature/ipad-pane-polish-shots/`.

| Criterion | Action | Result | Artifact |
|---|---|---|---|
| SC1 | Open report.md, tap expand, then tap the top-left button | Full width shows a circle chevron only; tapping it returns to the split | `05-full-width.png`, `06-back-to-split.png` |
| SC2 | Open report.md in the pane | Its card matches its neighbours: no blue, no "Open" | `05-full-width.png` (before expand), `06-back-to-split.png` |
| SC3 Sessions | Tap Fork session feature, then ↓ and ↑ | Fill only, no ring; selection follows the arrows | `15-tap-fork.png`, `16-key-down.png`, `17-key-up.png` (the same steps drew the ring on attempts 1–2: `08`, `09`, `12`–`14`) |
| SC3 Tasks | Tap Morning digest, then ↓ and Tab | Fill only, no ring | `20`–`22`; without the helper also no ring: `b2`–`b9` |
| SC4 | `flowdeck test` FilePaneSizingTests, VideoPictureInPictureTests, FilePaneUITests (both) | 10/10 passed, 0 skipped | test summaries in the session log |
| SC4 | `swift test` in `ios/LFGCore` on the Pro | 582 Swift Testing tests passed; XCTest 649 run, 1 skipped, 0 failures | Pro terminal output, Nov 3 |

**Independent audit (Nov 3): PASS** on every criterion, from the auditor's own fresh build and captures. Report: `.codex/evidence/20261103-225112-ios-visual-audit/evidence.md` (35 shots, comparison sheets, `pixel-checks.txt`). Its blue-ring pixel count was 0 in every capture and 1837 in the attempt-2 shot that shows the ring.

Audit limits, none caused by this diff:
- A synthetic drag on the resize handle did not resize the pane. Tapping the handle did (720 → 420). The gesture code is unchanged.
- In Tasks the sim never moved keyboard focus into the list, so "no ring while focused" there is proven only as far as the sim focuses it.
- After the pane closes, the arrow keys move nothing until a row is tapped. Not compared against the old build.
- The fixture has 3 sessions and 2 tasks; long scrolled lists were not tried.
- The Mac app was not rebuilt: the only shared-file change sits inside `#if os(iOS)`.

## Bugs

_None yet._
