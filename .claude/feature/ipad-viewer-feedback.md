# Feature: iPad file viewer feedback (2026-11-04)

## User Story

As Eugene reading files on the iPad, I want a bigger sheet, images and videos that show whole, a full-screen
option, and no Files pill, so that I can see files without zooming out and the composer stays clean.

## User Flow

1. Portrait: tap a file card. It opens in a sheet that fills the screen below the status bar.
2. An image or video shows its whole height at once.
3. The sheet header has Split and Full screen. Full screen fills the window; the chevron or the collapse
   button returns to the sheet. From the split, Full screen returns to the split.
4. Landscape keeps the side pane and Full width, and images there also show whole.
5. Files & links opens from the session sheet tile, as on iPhone. No Files pill above the composer.
6. Rotating keeps the open file: the portrait sheet becomes the landscape side pane, and back.

## Success Criteria

- [x] SC1: The portrait sheet is bigger than the old 580×650 form sheet. — **Verify by:** screenshot; UI test asserts reader width > 80% of the window.
- [x] SC2: Images in the pane rest at the whole image (sheet, split, side, full screen) and refit after a resize. Videos show whole. iPhone keeps fit-to-width (by code: `fitsWholeImage` defaults to false; not run on an iPhone sim). — **Verify by:** `ImageFit` tests; screenshots with a 1206×2622 screenshot and a 720×1564 video.
- [x] SC3: Full screen is offered next to Split in the sheet and next to Sheet in the split; it returns to where it came from. — **Verify by:** `headerOffersFullScreenBesideTheSplit`, `fullScreenIsInlineFromEveryPresentation`; UI test `testPortraitReaderGoesFullScreenFromSheetAndSplit`; screenshots.
- [x] SC4: No Files pill on iPad; Files & links opens from the session sheet. — **Verify by:** UI test `testHistoricalSourceRevealIsVisibleBelowHeader` (opens Files from the sheet, asserts no pill); screenshots.
- [x] SC6: Rotating with the file open keeps it open (sheet → side pane → sheet). — **Verify by:** UI test `testRotationKeepsTheOpenFile`, which fails on the old dismiss rule.
- [x] SC5: No regressions. — **Verify by:** `swift test` in LFGCore; FilePane UI tests; app unit tests.

## Decision Log

- Sheet size: `.presentationSizing(.page)`, the native large iPad sheet. On the 11-inch in portrait it fills
  the screen below the status bar, so Full screen from the sheet gains only the top margin. On the 13-inch the
  page sheet is narrower than the window. Flagged to Eugene rather than inventing a photo-viewer mode.
- Full screen reuses the existing full-width layout (`fullWidth`), now allowed in portrait. One state, one
  button style, and rotation carries it across orientations. The landscape label stays "Use the full width".
- Images: `ZoomableScrollView` gets `fitsWhole`; the pane sets it, iPhone keeps fit-to-width. The resting
  zoom is now refit when the view resizes while the user has not zoomed (pane handle, full screen, rotation).
- Full screen is kept as built (Eugene agreed, Nov 4): it matters from the split and on the 13-inch; no
  photo-viewer mode.
- Rotation bug (found by the audit, asked by Eugene): the sheet's `onDismiss` closure is kept from when the
  sheet appeared, so its `presentation` read the old portrait window size and called `close()` when rotation
  moved the file inline. Now `synchronize()` sets a `@State` flag when the layout takes the sheet away, and
  only a dismissal without that flag (a swipe down) closes the file. Docking never hit this because
  `portraitDocked` is read through the live binding.
- Videos already used `.resizeAspect`; checked with a tall video, no change needed.
- The Files pill and its code are removed from `ComposerPillRow`. The new-file dot went with it; the
  session sheet's Files & links tile shows the count, as on iPhone. `FilePaneState.unseen` is now unused by UI.
- Worktree `claude/ipad-viewer-feedback` from main `e1ead2e`, because main's tree holds another session's
  uncommitted edits to `SessionDetailView.swift`. The change there is three non-adjacent hunks.

## Verification Evidence

iPad Pro 11-inch sim `cc-34546475-ipad` on the Pro, dark, private fixture `~/.lfg/pane-fixture-viewer-34546475`
(adds `tall.png` 1206×2622 and `tall.mp4` 720×1564). Shots in `.claude/feature/ipad-viewer-feedback-shots/`.

| Criterion | Action | Result | Artifact |
|---|---|---|---|
| SC1 | Open tall.png in portrait | Sheet fills the screen below the status bar | `03-sheet-tall-image.png` |
| SC2 | tall.png in sheet, split, full screen, side, full width; tall.mp4 in split and side | Whole image and video every time | `03`, `06`, `07`, `09`, `10`, `11`, `12` |
| SC3 | Sheet → Full screen → back; Split → Full screen → chevron | Returns to the sheet, then to the split | `04`, `05`, `07`, `08` |
| SC4 | Portrait and landscape session views; session sheet → Files & links | No pill; index opens in the pane | `02`, `10`, `13`, `14` |
| SC6 | `testRotationKeepsTheOpenFile` with the fix, then with the old `onDismiss` line put back | Fix: passed. Old rule: failed at "Rotating keeps the file open" | terminal |
| SC5 | FilePaneUITests (4) + FilePaneSizingTests + VideoPictureInPictureTests after the fix | 12/12 passed | terminal |
| SC5 | `swift test` (LFGCore) | 651 XCTest (1 skipped), 588 Swift Testing, 0 failures | terminal |
| SC5 | `flowdeck test` FilePaneUITests (3), FilePaneSizingTests, VideoPictureInPictureTests | 11/11 passed | terminal |
| SC5 | `flowdeck test --skip LFGUITests` | 22/22 passed | terminal |

**Independent audit (Nov 4): PASS** on all five criteria, from the auditor's own build, captures and UI test run
(3/3). Report: `.codex/evidence/20261104-140827-ios-visual-audit/evidence.md`. Its limits: header buttons were
tapped by point (FlowDeck's tree hides them in the sheet); iPhone fit-to-width not checked; on the 11-inch,
Full screen from the sheet grows the image only from 456×992 to 460×1002.

Found by the audit: rotating to landscape with the portrait sheet open closed the file (its shots `18`,
`30a`–`30b`). Fixed as SC6.

Found, not caused by this change: tapping the session title shows a full-title banner; it stays drawn over
the pane header after a file opens (`14-files-index-from-sheet.png`).

## Bugs

_None open._
