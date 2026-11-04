# iPad file pane — design (Oct 23)

**Ask:** on iPad landscape, tapping a file, image, video or link in a session should open it side by side
with the transcript, not over it. Look at how other apps do multi-panel layouts first, then mock it up.

**Where it lives:** LFG UI Map canvas, page "iPad file pane (Oct 23)" (`ipad-files`, boards `ia-*`).
<https://claude.ai/artifact/F2B1MNbv5oxuscm237M9sD>

**Research:** `research.md` in this folder (30 apps + Apple HIG, with sources). Shots: `shots/`.
**Generators:** `canvas-gen/` (`gen.py` → `ia-proto` + importer boards; `gen_patterns.py` + `patterns.json`
→ `ia-patterns`; `notes.py` → the page's stickies). Re-run, then publish `canvas/project/*` to the canvas.

## Recommendation: Option A

- Tap a file card, a link, or the Files pill → the file opens in a pane on the right. Transcript, pills
  and composer stay live on the left.
- The list steps aside by a **width rule**: it stays only if the transcript keeps ≥400pt and the pane gets
  ≥600pt. Hides on the 11-inch, stays on the 13-inch. Closing the pane restores the previous layout.
- **Two widths, one handle.** Wide 720pt (docs, web pages, Files & links; transcript becomes a 460pt
  column). Narrow 420pt (images, videos — mostly portrait phone captures; transcript keeps its full 720pt
  column). Drag past either end: close / full width. Remembers the last width per kind.
- One pane, **replaced on tap** (no tabs). The open file's card turns blue with "Open". The transcript never
  auto-scrolls.
- Header: back to Files & links · name + folder + age · expand + ••• · close. Web pages put the address in
  the header. ••• = Show in transcript, Copy path (links add Open in Safari). No Share, no new window, no
  source view (Eugene, Oct 23).
- The pane is a card with a 64pt header inside it (circle buttons) and the file in a black area inset 8pt.
  Its buttons sit 10pt below the transcript bar's; Eugene accepted that on Oct 23 after trying a
  containerless pane and a squeezed 44pt header — the card needs the room at the top.
- Media strip for the session's images and videos. Video keeps native controls + Picture in Picture.
- Full width: a chip with the session's status and name brings the transcript back.
- List button: list as an overlay with a dim scrim; badge shows the needs-input count while hidden.
- Per-session memory of the open file.
- **Portrait:** a sheet by default. A split button in the header docks the file on top, with the transcript
  live below; the handle snaps the file at 40 / 55 / 70% of the height (tap steps through, drag to the top
  edge closes, to the bottom edge returns to the sheet). The choice is remembered; the keyboard drops the
  file to 40%. Slide Over and windows under ~600pt always use the sheet.

**Option B** (list stays, 390pt third column) is drawn and rejected: on the 11-inch the file gets a
phone-width column — the Claude iPad complaint (anthropics/claude-code#100553). Its one strength returns on
the 13-inch through A's width rule.

## Build notes (from the code map)

- FE reuse: every viewer already lives in `FileViewerSheet` (`ios/LFG/RichContent.swift`).
- FE change: `openInlineFile` (`SessionDetailView.swift`) is the single entry point — on a wide window it
  fills the pane instead of presenting the sheet. Paging already exists in `FilePreviewSequence`.
- FE new: two-pane container inside the detail column (not SwiftUI `.inspector`), handle + snaps, selected
  card state, media strip, full width, the portrait split + handle, an in-app WKWebView for `.html` and links.
- FE new (client only): message id on `TranscriptAttachment` for "Show in transcript".
- BE: none.

## Open questions for Eugene

All decided Oct 24:

- **Links open in the pane**, with Open in Safari in •••. The pane's web view keeps its own sign-ins (the
  first private page asks once).
- **A new file never takes over the pane.** Its card appears in the transcript; the Files pill's count turns
  blue with a dot; Files & links marks it New. Opening the file or the list clears the dot. Board
  `ia-a-newfile`.
- **The open file reloads in place** when the transcript shows the agent rewrote it; the meta line says
  "updated just now". No server change. Board `ia-a-updated`.
- **Keyboard:** Esc closes the pane in this pass; Cmd-[ / Cmd-] wait for the keyboard pass.

## Changes after reviewing the built app (Nov 3)

Eugene reviewed the shipped build's screenshots (`built-shots/`) and cut three pieces of chrome.
Built in worktree `claude/ipad-pane-polish`; record `.claude/feature/ipad-pane-polish.md` there.

- Full width: the way back is a plain circle chevron, like the other header buttons. No session name or
  status dot (this replaces "a chip with the session's status and name" above).
- The open file's transcript card has no selected state: no blue fill, border or "Open" (this replaces
  "the open file's card turns blue with Open" above).
- A selected row in the Sessions and Tasks sidebars is its fill only. The border was the iPadOS keyboard
  focus ring.
- The canvas boards (`ia-*`) still draw the old chip and the Open card; update them when the canvas is
  reachable again.
