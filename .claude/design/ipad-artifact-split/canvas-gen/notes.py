NOTES = {
 'ifT0': dict(x=0, y=-300, kind='title1', maxW=2400, text='Inspiration: how other apps put a file beside a conversation'),
 'ifTA': dict(x=0, y=1500, kind='title1', maxW=6370, text='Option A (recommended): the file opens beside the transcript, and the list steps aside'),
 'ifTP': dict(x=0, y=4860, kind='title1', maxW=3576, text='Portrait: a sheet by default, or a top and bottom split'),
 'ifTB': dict(x=0, y=6490, kind='title1', maxW=2500, text='Option B: the list stays, and the file opens in a narrow third column'),
 'ifHowTo': dict(x=-1200, y=1800, w=520, fill='gray', text='''How to read this page

Row 1 is the inspiration: eight patterns from about 30 apps, and which ones lfg takes.

The first board in the Option A row is a working prototype. Press Play, then tap any file card, the PR link or the Files pill. Tap the handle between the two columns to switch the pane width. Back, expand, ••• and close all work. In the portrait row, the split button and the handle work too.

Every other A and B board is the same prototype, opened in one state, so a change to the prototype updates them all.

Sample session: "Fork session feature", with the same six files and two links as the S2 Files & links board. The screenshots and pages inside the pane are placeholders.

Frames: iPad Pro 11-inch landscape (1210 × 834) and portrait (834 × 1210), plus one 13-inch board (1376 × 1032).'''),
 'ifResearch': dict(x=-600, y=0, w=520, fill='blue', text='''What the research found

- Most chat-plus-file apps now split the window and give the file the wider side: Claude web (about 50/50), Gemini (36/64), ChatGPT Codex (26/74), Swift Playgrounds.
- The Claude iPad app is the warning. Its artifact pane is a fixed third of the screen with no expand button, so web pages get a phone layout. Users complain about this most.
- Apple's iPad guidance: use the big screen to cut full-screen transitions, and make every layout change undo itself when it ends.
- Apple's inspector column is built for details (225 to 400pt). Copy its behaviour (trailing, resizable, a sheet when narrow), not its width.
- ChatGPT dropped its side canvas in May 2026 for inline blocks that open full screen. The expand button matters as much as the split.
- No app stacks files in the pane. A new tap replaces the old file.

Full notes and sources: .claude/design/ipad-artifact-split/research.md'''),
 'ifRules': dict(x=-600, y=1800, w=520, fill='green', text='''How option A behaves

- Tap a file card, a link or the Files pill. The file opens in a pane on the right. Links open in the pane too, and ••• has Open in Safari (decided Oct 24). The transcript, pills and composer stay live on the left.
- The list steps aside unless the transcript keeps 400pt and the pane gets 600pt. So it hides on the 11-inch and stays on the 13-inch.
- Two widths, one handle. Wide (720pt) for documents, web pages and Files & links: the transcript becomes a 460pt column. Narrow (420pt) for images and videos, which are mostly portrait phone captures: the transcript keeps its full 720pt column. Drag past either end to close the pane or fill the screen. The pane remembers the last width for each kind of file.
- The open file's card turns blue and says Open. A new tap replaces the file. The transcript never scrolls by itself.
- Header: back to Files & links, the name with its folder and age, expand and •••, close. ••• holds Show in transcript and Copy path (a link adds Open in Safari). A web page shows its address in the header.
- Images and videos get a strip to step through the session's media.
- Expand fills the screen. A chip with the session's status and name brings the transcript back.
- The list button shows the list over everything, dimmed. Tap outside to hide it. While the list is away, the button shows the needs-input count.
- Close (or Esc) puts back the layout you had.
- A new file from the agent never replaces what you are reading. Its card appears in the transcript, the Files pill turns its count blue with a dot, and Files & links marks the file New. Opening the file or the list clears the dot.
- When the agent rewrites the open file, the pane reloads it in place and its meta line says "updated just now". The client sees the edit in the transcript, so this needs no server change.
- Each session remembers its open file.
- Portrait: see the portrait row. A sheet by default, or a top and bottom split.'''),
 'ifBuild': dict(x=-600, y=2754, w=520, fill='orange', text='''What exists and what is new

FE reuse: every viewer. The zoomable image, the video player (with Picture in Picture), PDF, Markdown and Quick Look already live in FileViewerSheet. The pane hosts the same views.

FE change: one entry point. Every file tap goes through openInlineFile. On a wide window it fills the pane instead of opening the sheet.

FE new: a two-pane container inside the session's detail column, the handle and its snap widths, the blue card state, the media strip, full width, and the portrait split with its handle. Not SwiftUI .inspector: it is sized for details and has an iPadOS 26 bug that hides the sidebar button.

FE new: an in-app web view for HTML files and links. Today .html falls back to Quick Look, and links leave for Safari. It does not share Safari's sign-ins: the first private page (a GitHub PR) asks you to sign in once, and the app's own web data store keeps that sign-in.

FE new, client only: Show in transcript needs the message id on each attachment. Today an attachment keeps only its path and time.

BE: nothing. Files stream from /api/file as today, and the client builds the file list from the transcript.'''),
 'ifOpen': dict(x=-600, y=3708, w=520, fill='purple', text='''Decisions (Oct 23-24)

- Links open in the pane, with Open in Safari in •••.
- A new file never takes over the pane. The Files pill shows it with a blue dot (board "a new file arrives while you read").
- The open file reloads in place when the agent rewrites it (board "the open file was rewritten").
- Keyboard: Esc closes the pane in this pass. Cmd-[ and Cmd-] to step through files wait for the keyboard pass.
- No Share, no Open in new window, no source view.
- The pane stays a card with room at the top. Its buttons do not need to line up with the transcript bar.'''),
 'ifWhy': dict(x=-600, y=6790, w=520, fill='gray', text='''Why A, not B

- On the 11-inch, three columns leave the file 390pt. A Markdown file reads like a phone, a web page gets its phone layout, and an image is no bigger than in today's sheet. This is the Claude iPad complaint.
- A gives the file room and keeps one column you can talk in. The list button's badge still shows when another session needs you.
- B's one strength, the list that stays, comes back by itself on the 13-inch through A's width rule.'''),
}
