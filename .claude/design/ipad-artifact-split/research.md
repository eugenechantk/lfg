# iPad artifact split: research

Date: 2026-10-23. Question: how do other apps put a "detail / preview / artifact" pane beside a primary
conversation or list, and what should lfg do on iPad landscape?

**How to read this.** Each app section answers the eight questions where evidence exists: trigger, geometry,
sidebar interplay, multiple items, expand/close, narrow fallback, media chrome, linking back. Items marked
**(training knowledge)** come from memory, not a source fetched today. Treat them as likely but unverified.
Mobbin measurements are from 768px-wide screenshots, so ratios are approximate (about ±3%).

**The lfg baseline today** (read from the code, not researched):

- `ios/LFG/RootView.swift` uses a two-column `NavigationSplitView` with `.balanced` style. The sidebar is
  `min 300 / ideal 360 / max 460` pt. `columnVisibility` toggles `.doubleColumn` and `.detailOnly`.
- `ios/LFG/RichContent.swift` has `FileViewerSheet`, a full-screen pager. It runs over a `FilePreviewSequence`
  (`ios/LFGCore/Sources/LFGCore/MediaRefs.swift`), which already uses the session-wide "Files & Links" order.
- So lfg already has the two hard parts: an ordered artifact list per session and per-type renderers.
  The new work is mostly the layout.

---

## 1. Platform guidance (Apple)

Sources fetched live today with the `apple-hig` helper (Apple's HIG JSON), plus WWDC25 transcripts.

- **Split views (HIG, updated 2025-06-09).** On iPadOS a split view has two panes (like Mail) or three (like
  Keynote). "Account for narrow, compact, and intermediate window widths." "Persistently highlight the current
  selection in each pane that leads to the detail view." On macOS: "Set reasonable defaults for minimum and
  maximum pane sizes", "Consider letting people hide a pane", "Provide multiple ways to reveal hidden panes"
  (a toolbar button, a menu command, a keyboard shortcut). It prefers a 1pt thin divider.
  [HIG: Split views](https://developer.apple.com/design/human-interface-guidelines/split-views)
- **Sidebars (HIG, updated 2026-06-08).** "Consider letting people hide the sidebar… in iPadOS, people expect to
  use the built-in edge swipe gesture." "Avoid hiding the sidebar by default." On macOS: "Consider
  automatically hiding and revealing a sidebar when its container window resizes… reducing the size of a Mail
  viewer window can automatically collapse its sidebar."
  [HIG: Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- **Layout (HIG, updated 2026-09-09).** "Determine layout based on size classes, not device type or
  orientation." "Keep functionality the same as size classes change… you can change the amount of
  functionality that's visible onscreen."
  [HIG: Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- **Designing for iPadOS.** "Take advantage of the large display to elevate the content people care about,
  minimizing modal interfaces and full-screen transitions." This argues directly against today's full-screen
  viewer on iPad landscape.
  [HIG: Designing for iPadOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ipados)
- **Windows (HIG).** iPadOS has a full-screen mode and a windowed mode, and windows resize freely. "Consider
  letting people use a gesture to open content in a new window", for example a pinch on a Notes item. For a
  single file you can use `QLPreviewSceneActivationConfiguration` instead of building your own window.
  When an app shows an inspector, it "typically presents information on the trailing side of a split view".
  [HIG: Windows](https://developer.apple.com/design/human-interface-guidelines/windows)
- **Going full screen (HIG).** "Prioritize content by temporarily hiding toolbars and navigation controls…
  let people restore the hidden elements with a familiar gesture." "Let people choose when to exit."
  [HIG: Going full screen](https://developer.apple.com/design/human-interface-guidelines/going-full-screen)
- **Slide Over is back** in iPadOS 26.1 as a resizable floating window that remembers its width. So an lfg
  window can be very narrow, and the layout must fall back.
  [MacSparky](https://www.macsparky.com/blog/2025/11/slideover-returns-to-ipados-26-sort-of/),
  [Engadget](https://www.engadget.com/mobile/tablets/apple-is-bringing-back-slide-over-in-ipados-261-190036025.html)
- **WWDC25 "Elevate the design of your iPad app".** "Make sure that any change in layout is non-destructive.
  Resizing an app should not permanently alter its layout. Be opportunistic about reverting back to the
  starting state." "Apps that don't use a tab bar can also adapt its navigation by collapsing its columns
  down." [WWDC25 208](https://developer.apple.com/videos/play/wwdc2025/208/)
- **UISplitViewController in iPadOS 26** gained an `.inspector` column and drag-to-resize separators.
  New properties are `minimum/maximum/preferredInspectorColumnWidth` and
  `preferredInspectorColumnWidthFraction`, with the same set for the secondary column. "When collapsed, the
  split view controller… presents the inspector column as a sheet." There are new `didShow` / `didHide`
  delegate callbacks and a `splitViewControllerLayoutEnvironment` trait (expanded or collapsed).
  [WWDC25 282](https://developer.apple.com/videos/play/wwdc2025/282/),
  [Seb Vidal: What's new in UIKit 26](https://sebvidal.com/blog/whats-new-in-uikit-26/)
- **SwiftUI `.inspector(isPresented:)`** shows "as a trailing column in a horizontally regular size class, but
  adapt[s] to a sheet in a horizontally compact size class". Width is set with
  `inspectorColumnWidth(min:ideal:max:)`, and Apple's example is ideal 225 / max 400 / min 150. "Only some
  platforms enable flexible inspector columns."
  [Apple docs](https://developer.apple.com/documentation/swiftui/view/inspector(ispresented:content:)),
  [inspectorColumnWidth](https://developer.apple.com/documentation/swiftui/view/inspectorcolumnwidth(min:ideal:max:))
  - Known iPadOS 26 bug: `.inspector` on the *detail* of a `NavigationSplitView` makes the sidebar toggle vanish
    when the sidebar is hidden. The workaround is to attach it to the split view itself.
    [Apple forums 799794](https://developer.apple.com/forums/thread/799794)
  - On iPadOS 17 the inspector showed as a modal overlay when the window was regular-width but not full-screen
    landscape. [Nil Coalescing](https://nilcoalescing.com/blog/InspectorInSwiftUI/)
- **`NavigationSplitViewStyle`.** `.balanced` "reduces the size of the detail content to make room" for leading
  columns. `.prominentDetail` "attempts to maintain the size of the detail content", so leading columns overlay
  it. [balanced](https://developer.apple.com/documentation/swiftui/navigationsplitviewstyle/balanced),
  [prominentDetail](https://developer.apple.com/documentation/swiftui/navigationsplitviewstyle/prominentdetail)

**What this adds up to:** Apple's own word for a trailing pane is "inspector". Apple means *supplementary
details*, with an example width of 225pt and a cap near 400pt. An lfg artifact is *primary content* that
wants width. Use the inspector's behaviour (trailing, resizable, becomes a sheet when compact). Do not use
its width.

---

## 2. iPad apps

### Claude iPad app (artifacts)
- Trigger: tap an artifact link in a conversation. It opens in a trailing preview pane, and the conversation
  stays visible. [anthropics/claude-code#100553](https://github.com/anthropics/claude-code/issues/100553)
- Geometry: the pane is "about a third of the screen width", fixed. "A dashboard or mockup page laid out for a
  tablet or desktop is squeezed into a phone-sized column." No divider, no full-screen toggle. (Issue open,
  October 2026.)
- Narrow fallback: on iPhone "the same link opens the artifact using the whole screen, which works well."
- **Lesson: this is the anti-pattern to avoid.** An inspector-width pane is too narrow for HTML or PDF
  artifacts, and the missing expand button is the top complaint.

### ChatGPT iPad (canvas / file preview)
- Canvas was removed from ChatGPT on 2026-05-28. Writing blocks replaced it, and they live *inside* the thread
  and open full-screen. Code blocks got "split-screen code review views" in February 2026.
  [Fello AI](https://felloai.com/chatgpt-canvas/)
- Before that, iOS only partly supported canvas: you could open an existing canvas "in a separate view"
  (full screen). [TestingCatalog on Threads](https://www.threads.com/@testingcatalog/post/DArPqWFgbP4/chatgpt-canvases-are-also-supported-on-ios-partiallyyou-cannot-start-a-new-conve)
- File and image previews on iPad open as a full-screen viewer over the chat **(training knowledge)**.
- **Lesson: OpenAI moved away from a persistent side panel for documents and toward inline-plus-full-screen.**
  For lfg that is a signal that "expand to full" matters as much as the split.

### Apple Mail, Notes, Files (iPadOS 26)
- Mail: in landscape it has three columns (mailboxes, list, message). An "Expand Message" button hides the
  list. You can drag the divider to collapse the mailbox column. "Open in New Window" gives a full window, but
  that window has no next/previous navigation.
  [Apple Community](https://discussions.apple.com/thread/256138223),
  [Apple Support](https://support.apple.com/guide/ipad/check-your-email-ipad99a3ef9e/ipados)
- Mail opens Compose in a *new window* so both stay visible (HIG Windows). Notes: pinch an item to open it in a
  new window (HIG Windows).
- Notes: folders, list and note in columns. A full-screen button in the note collapses the other columns
  **(training knowledge)**.
- Files: column view ends in a preview column with metadata, which works like an inspector. Tapping a file
  opens Quick Look full screen, or the new Preview app (default in iPadOS 26).
  [TidBITS Talk](https://talk.tidbits.com/t/restoring-quick-look-in-files-app/32402),
  [iDrop News](https://www.idropnews.com/how-to/how-to-restore-the-classic-preview-experience-in-ios-26/254519/)
- Quick Look (`QLPreviewController`) swipes left and right between items, with share and markup in the
  toolbar, and closes with a swipe down **(training knowledge)**. lfg already uses it in `RichContent.swift`.
- Preview on iPadOS 26 puts metadata in an inspector column beside the photo (WWDC25 282).

### Swift Playgrounds (code + live view)
- App Preview sits "in the right sidebar" by default and updates live.
  [Apple Support](https://support.apple.com/guide/playgrounds-ipad/hide-show-or-resize-an-app-preview-itc2055d1b82/ipados)
- Controls: Show Preview (toggle), **Expand Canvas** (preview fills the screen), **Contract Canvas** (back to
  the side). In playground books, you drag the resize handle between code and live view "to expand one or the
  other to full screen".
- **Lesson: there are three states (hidden, side, full), and each has a one-tap button.** Dragging the handle
  past the edge also goes to full.

### Keynote / Pages / Numbers (inspector)
- HIG uses Keynote as the iPadOS three-pane example (navigator, canvas, inspector)
  ([HIG Split views](https://developer.apple.com/design/human-interface-guidelines/split-views)).
- The Format (paintbrush) button opens format controls on the trailing side. The slide navigator is on the
  leading side. In iPadOS 26 the full option set is also in the new menu bar.
  [Apple Support](https://support.apple.com/guide/keynote-ipad/whats-new-tan700f60676/ipados)
- The trailing panel is narrow and fixed. It overlays or pushes the canvas depending on width **(training
  knowledge)**.

### Final Cut Pro / Logic Pro for iPad
- FCP: browser, viewer and timeline resize by dragging handles: the browser's top-left corner (left/right) and
  the timeline's top edge (up/down). Browser buttons hide the browser to give the viewer room. The inspector
  opens on the *left*, from an Inspect button at bottom-left.
  [Apple Support: customize the Edit screen](https://support.apple.com/guide/final-cut-pro-ipad/customize-the-edit-screen-dev8b472bcb8/ipados)
- FCP viewer: More, then Full Screen, or More, then **Picture in Picture**. PiP is a small draggable,
  resizable window over the interface.
  [Apple Support: playback](https://support.apple.com/guide/final-cut-pro-ipad/customize-playback-settings-devb1a504a87/ipados)
- Logic: the inspector opens from a button on the left of the view control bar. A plug-in's resize handle can
  be *dragged*, or *tapped* to jump to maximum size and tapped again to go back.
  [Apple Support: Logic interface](https://support.apple.com/guide/logicpro-ipad/logic-pro-interface-lpip33be754d/ipados),
  [Details view](https://support.apple.com/guide/logicpro-ipad/intro-to-details-view-lpip10a08756/ipados)
- **Lessons:** (1) a resize handle you can tap to toggle max size is a good touch affordance. (2) PiP for video
  lets a clip keep playing while the pane closes.

### Slack iPad (thread pane)
- Two-column layout on iPad since 2022: the channel list, then the conversation.
  [XDA](https://www.xda-developers.com/slack-ipad-update-desktop-two-column-layout/),
  [Slack blog](https://slack.com/blog/productivity/whats-new-in-slack-ipad-app-split-screen)
- Landscape support for iOS arrived in late 2025. Threads open in a side panel when the window is wide enough
  ([Slack accessibility changelog](https://slack.com/help/articles/50668520513939-Accessibility-changelog),
  details not confirmed).
- Desktop behaviour is in section 3.

### GoodNotes / Notability (two docs side by side)
- GoodNotes: document **tabs** inside the app. Side by side works only through iPadOS multiwindow: drag a
  document or page to the screen edge, or use the tab menu's "Open in New Window".
  [GoodNotes support](https://support.goodnotes.com/hc/en-us/articles/7353757107215-Open-Goodnotes-in-multiple-windows-on-iPadOS)
- Notability: native **multi-note**. Drag a note from the Note Switcher into the editor to split, then "drag
  the middle spacer to adjust the note size".
  [Paperlike](https://paperlike.com/blogs/paperlikers-insights/app-review-goodnotes-vs-notability)
- **Lesson:** an in-app split with a draggable spacer beats "use iPadOS multiwindow". It keeps one window and
  one selection.

### Working Copy (git client)
- Hierarchical navigation from repos to directories to files. On wide iPads, actions move into the top bar
  instead of sheets. A preview toggle switches between editing and previewing Markdown or HTML (double-tap
  the button). For live HTML preview the manual suggests putting Safari side by side in iPadOS Split View.
  The diff view is a two-panel split that "requires the screen to be wide".
  [Working Copy manual](https://workingcopy.app/manual/)
- **Lesson:** source/rendered is a *mode of one pane*, not a second pane.

### Notion iPad
- Notion has three ways to open a page: Side peek, Center peek and Full page, set per database view ("Open
  pages in"). Table, board, list and timeline views default to side peek. Gallery and calendar default to
  center peek. The release says this applies across apps.
  [Notion release 2022-07-20](https://www.notion.com/releases/2022-07-20),
  [Notion help](https://www.notion.com/help/views-filters-and-sorts)
- Whether side peek actually shows on iPad, and how wide it is there, was not verified.

### Linear iPad
- The Linear Mobile app on iPad is the phone layout scaled up. A reviewer notes it lacks basics like
  switching list and board views. No evidence of a peek or detail split on iPad.
  [App Store](https://apps.apple.com/us/app/linear-mobile/id1645587184)
- No useful iPad pattern. See desktop.

### Obsidian iPad (split panes)
- In tablet mode you drag a tab to split panes side by side. **You cannot drag-resize the split on iPadOS.**
  Users ship CSS snippets that preset ratios like 60/40, and a resize plugin was archived. Phones don't
  split at all.
  [Obsidian forum](https://forum.obsidian.md/t/simple-css-snippet-to-resize-split-panes-on-ipad-e-g-60-40-hotkey-toggle/102737)
- **Lesson:** users want a resizable divider badly enough to hack one in. If you can't do free resize, preset
  ratios with a toggle are the fallback.

### Lightroom iPad
- Edit panels sit on the *right side in both orientations* on iPad. (On a phone in portrait they move to the
  bottom.) Users complain that in portrait the side panel wastes image space. A setting only mirrors the UI
  for left-handed use.
  [Digital Photography School](https://digital-photography-school.com/editing-with-lightroom-mobile/),
  [Adobe community](https://community.adobe.com/questions-680/change-panel-position-on-lightroom-mobile-918725)
- **Lesson:** keeping a side pane in iPad portrait is a known complaint. Fall back in portrait.

---

## 3. Desktop and web apps

### Claude web / desktop (artifact panel)
- Trigger: tap the artifact card in the thread ("Interactive artifact"). "Expands to the split pane without
  losing the chat history on the left."
  [AI UX Playground teardown](https://aiuxplayground.com/teardowns/claude/artifacts)
- Geometry: about **50/50**. When the panel opens, the left sidebar collapses to an icon rail. The chat keeps
  its own column with a centred composer.
  [Mobbin: Claude chat + code artifact](https://mobbin.com/screens/587db0a6-6f7d-4a6a-b1ac-80ea594f7c7a)
- Panel header: Preview / Code toggle (eye and `</>`), Copy, Publish, refresh, close (X) at top-right. Preview
  and Code "are two modes of one pane, not separate destinations."
- Expand: "Full-width artifact mode hides the chat entirely. Users lose conversational context until they
  dismiss or resize." Artifacts are also saved in a separate Artifacts tab, outside the conversation.
  [Claude Academy](https://academy.claude.com/courses/claude-101/creating-with-artifacts)
- Claude Design (claude.ai/design): the chat is narrow (**~26%**) on the left. The canvas (~74%) has **tabs**
  (Design Files, sketch, Pricing.html, each closable). A Present menu offers In this tab / Fullscreen /
  New tab.
  [Mobbin: tabs + present menu](https://mobbin.com/screens/93d5daee-b553-4a70-b7ad-efdce0e6d7a9),
  [Mobbin: canvas](https://mobbin.com/screens/b74052b8-bc0e-476c-80cc-416744bb655f)

### Claude Code desktop (closest analog: agent sessions)
- "To open a file Claude mentions, click its path in the chat." Other panes (Terminal, Changes/diff, Browser,
  Files, Plan, Tasks, Subagent, iOS Simulator) open from title-bar buttons.
  [Claude Code desktop docs](https://code.claude.com/docs/en/desktop)
- "Drag a pane by its header to reposition it, or drag a pane edge to resize it." Cmd+\ closes the focused
  pane. Panes can pop out into their own window and dock back.
- The Browser pane "renders HTML, PDF, images, and video from your project". One viewer covers every media
  type. [AI Catchup](https://aicatchup.com/news/claude-code-desktop-redesign)
- A "session details panel" (cards: where it runs, changes, context) "appears… while the chat is wide enough
  for it". It hides automatically by width, and a title-bar toggle hides it by hand.
- The trailing artifact panel was once stuck narrow because of a width-probe bug with
  `.inspectorColumnWidth`. [watchtower PR #239](https://github.com/aiwatchtowers/watchtower/pull/239) (third-party
  client, same API trap).

### ChatGPT canvas (historical) and ChatGPT Codex web
- Canvas (2024 to May 2026): it opened automatically in the right half, with the chat on the left. X on the
  canvas title closed it. An "Open canvas" icon or tapping the canvas card in chat reopened it.
  [Zapier](https://zapier.com/blog/chatgpt-canvas/), [Fello AI](https://felloai.com/chatgpt-canvas/)
- Codex task page (chatgpt.com/codex): the conversation and summary are a narrow **~26%** left column. A
  **Diff | Logs** tabbed pane takes ~74%, with a Split/Unified and Full/Incremental diff menu and a close X.
  The transcript has a "File (1) >" row that opens the diff.
  [Mobbin: diff](https://mobbin.com/screens/b97bb5e0-a0c2-40dc-807b-7d163a0bde7d),
  [Mobbin: logs](https://mobbin.com/screens/616a9efa-cfd6-4ff1-b831-2b7bd22eac70)
- Deep research: a trailing **Activity | Sources** panel (~26%) opens while the sidebar stays visible. That
  makes three columns, with the chat keeping a centred reading width.
  [Mobbin](https://mobbin.com/screens/1d43b453-a7b4-438f-8038-f9d5c16c903e)

### OpenAI Codex app (macOS, merged into ChatGPT desktop 2026-07-09)
- Layout: project sidebar, thread list, and a **Review pane** for diffs. It has inline or detached review modes
  and a "full-width" toggle plus a file-tree toggle.
  [ChatGPT & Codex changelog](https://learn.chatgpt.com/docs/changelog)
- A user request (duplicate of #16669, so a repeated ask): "I never want to review changes/diff in a side panel,
  and I don't want to click 2 buttons every time." They want full width by default, or the app to **remember
  the last layout**. [openai/codex#30703](https://github.com/openai/codex/issues/30703)

### Gemini canvas / other agent builders
- Gemini: the chat is **~36%** on the left. The canvas (~64%) is a rounded card with title, undo/redo,
  **Code | Preview** toggle, share/download, and close X. The sidebar collapses to a rail. **The artifact card
  in the chat is tinted while it is open**, which links the pane back to its message.
  [Mobbin](https://mobbin.com/screens/7245c1f5-8c31-4c14-979e-3ec03bc53af2)
- Google AI Studio, v0 and Mintlify follow the same shape: chat about 30–40% on the left, a workspace with
  Preview/Code tabs on the right.
  [AI Studio](https://mobbin.com/screens/915541ca-412a-436f-8632-fb2e22c2bd71),
  [v0](https://mobbin.com/screens/f2d792c6-ac0f-4c96-8023-be287b3aa365),
  [Mintlify](https://mobbin.com/screens/75a194a1-ad5f-44e0-b8eb-6f78bd5598ee)

### Cursor / VS Code
- VS Code: "Open Preview to the Side" (Cmd+K V) opens a Markdown preview in a second editor group, with
  scroll sync on by default. Drag a tab to an edge to make editor groups.
  [markdownpreview.net guide](https://markdownpreview.net/guides/vs-code-markdown-preview/)
- Editor groups have a draggable sash, and you can maximize a group **(training knowledge)**.
- Cursor 3 "Agents Window": agents are listed in the sidebar. "Split screen keeps a review open next to a
  chat." Clicking a file in the end-of-turn summary opens the Changes tab scoped to the last agent turn.
  [Cursor changelog](https://cursor.com/changelog/page/3),
  [review](https://www.openaitoolshub.org/en/blog/cursor-3-agent-first-review)

### Xcode (canvas + inspector)
- Editor Options, then Canvas, toggles the preview. Layout, then **Canvas on Right / Canvas on Bottom**, lets
  the user pick the split axis. The inspector is a separate trailing column with its own toggle.
  [Xcode help](https://help.apple.com/xcode/mac/current/en.lproj/dev79c94bf05.html)

### Slack desktop (thread / file panel)
- A thread or file opens a **trailing panel (~29%)** with a close X. The sidebar stays, and the channel
  narrows. PDFs show an inline thumbnail in both the channel and the thread.
  [Mobbin](https://mobbin.com/screens/bbcd789d-382c-48ca-9e03-7a46ffc00eda)
- "Open in split view" (right-click a conversation, or the ••• menu on a canvas) shows two conversations or
  files side by side. For more, open separate windows.
  [Slack help](https://slack.com/help/articles/47144721728275-Use-split-view-in-Slack)

### Linear (issue peek)
- Press Space on a focused issue to peek. Tap Space to keep it open, or hold to preview and release to close.
  ↑/↓ moves to adjacent issues *while the peek updates*. Esc closes. Peek is "similar to Quicklook in macOS".
  (Linear docs URL `linear.app/docs/peek` came up in search but returned 404 when fetched.)
- The inbox is three columns: sidebar, list, and detail with its own properties sub-panel.
  [Mobbin](https://mobbin.com/screens/17c8ce50-57d6-4a36-aeba-700bcb563fc6)

### Notion (side peek vs centre peek vs full page)
- The peek header has a mode switcher: Side peek / Center peek / Full page / New tab. The user can escalate
  one item, and set the default per view.
  [Mobbin: mode menu](https://mobbin.com/screens/8a6a33e6-ab41-4afb-9e51-dc4f108e39ee),
  [Mobbin: Open pages in](https://mobbin.com/screens/8859ba39-fc79-499d-a756-0085c2bf502f)
- In side peek, "keep your database items visible and interactive on the left".

### Arc browser split view
- Two to four tabs in one sidebar item. You make a split by dragging a tab to a page edge, Option-clicking a
  tab, or pressing Ctrl+Shift+=. Drag the divider to resize, with each pane floored at 15%.
  [warrenweb](https://blog.warrenweb.net/arc-split-views/),
  [allthings.how](https://allthings.how/how-to-open-tabs-in-split-view-in-arc-browser-on-windows/)

### macOS Finder preview pane / Quick Look
- View, then Show Preview, adds a trailing preview pane with a thumbnail, full metadata and Quick Actions in
  every view. Space opens a Quick Look window with a Full Screen button.
  [Apple Support: Preview pane](https://support.apple.com/guide/mac-help/use-the-preview-pane-in-the-finder-on-mac-mchl1e4644c2/mac),
  [Quick Look](https://support.apple.com/guide/mac-help/preview-a-file-mh14119/mac)

### Figma (right properties panel)
- UI3 uses fixed, docked, **resizable** panels. "Once you drag a sidebar to a custom width, Figma remembers it."
  Minimize UI (Shift+\) hides panels, and selecting an object brings the properties panel back.
  [Figma blog](https://www.figma.com/blog/behind-our-redesign-ui3/),
  [Pixel Fine](https://pixelfineconverter.com/blog/figma-ui-tips/)

### Bonus: conversation media galleries (Skype, hilos, Behance)
- Skype "Gallery" is a trailing panel listing every image and file in the chat. **Each item has "Reveal in
  conversation"**, which links back to the source message.
  [Mobbin](https://mobbin.com/screens/e3cf1281-595a-466c-a8f1-112dbd27b114)
- hilos shows a trailing "Files" grid, and Behance shows trailing "All / Images / Documents" tabs.
  [hilos](https://mobbin.com/screens/60bb0bc3-3788-48ef-9add-db2cb1768018),
  [Behance](https://mobbin.com/screens/ea99b63e-fc80-45b6-831e-8594ce6f8dff)

---

## 4. Patterns

The widths below assume lfg's sidebar at its 360pt ideal. iPad 11" landscape is 1194pt wide, iPad 13"
landscape is 1366pt, and 13" portrait is 1024pt.

### P1. Replace-detail
Used by: Mail, Notes, Slack iPad (two-column), Working Copy, lfg today (sidebar + transcript).
```
+-------+--------------------------+
| list  | detail (replaced on tap) |
+-------+--------------------------+
```
- Strengths: simple, and the reading width is generous.
- Weakness for lfg: the transcript and the artifact can't share the screen. Opening a file means losing the
  live transcript, which is the problem being solved.

### P2. Inspector column (narrow trailing pane)
Used by: Keynote, Xcode inspector, Preview (iPadOS 26), Finder preview pane, Slack thread panel (~29%),
ChatGPT deep research panel (~26%), Claude iPad artifact pane (~1/3), SwiftUI `.inspector`, UISplitViewController
`.inspector`.
```
+-----+-------------------+--------+
| nav | primary           | insp.  |
|     |                   | ~300pt |
+-----+-------------------+--------+
```
- Strengths: native API, keeps the sidebar, and becomes a sheet when compact for free.
- Weakness for lfg: the pane is phone-width, about 300–400pt. HTML pages, PDFs and wide images get squeezed.
  The Claude iPad issue is exactly this complaint. Fine for metadata, wrong for artifacts.

### P3. Co-equal resizable split (artifact split)
Used by: Claude web (~50/50), Gemini (36/64), ChatGPT canvas (50/50, removed), ChatGPT Codex (26/74), Claude
Design (26/74), Swift Playgrounds, VS Code preview to the side, Xcode canvas, Notability multi-note, Arc,
Claude Code desktop panes.
```
+--+--------------+-------------------+
|r | transcript   ‖ artifact          |
|a | ~40%         ‖ ~60%  [⤢] [x]     |
|i |              ‖ drag ‖ to resize  |
+--+--------------+-------------------+
```
- Strengths: both stay live, and the artifact gets real width. Most apps collapse the sidebar to a rail or hide
  it. This is the dominant pattern for chat + artifact in 2026.
- Weakness for lfg: there is no room for the 360pt sidebar on 11". You need clear rules for when the sidebar
  hides and comes back. A free divider needs snap points on touch, or it feels mushy.

### P4. Peek overlay
Used by: Notion side/centre peek, Linear peek (Space, ↑/↓), Quick Look, Finder Space.
```
+-----+--------------------+---------+
| nav | list (dimmed/live) | peek    |
|     |  > item  <-- ↑/↓   | overlay |
+-----+--------------------+---------+
```
- Strengths: fast, temporary, and you can step through items with ↑/↓. Easy to escalate to full page.
- Weakness for lfg: an overlay hides part of the transcript. lfg's transcript is live, so new messages arrive
  under the overlay. Fine as the *portrait* fallback, weak as the landscape default.

### P5. Full-bleed focus (expand toggle)
Used by: Swift Playgrounds Expand/Contract Canvas, Claude full-width artifact, Codex full-width review,
FCP full-screen viewer, Mail Expand Message, Notes full-screen, Logic tap-to-max handle, Quick Look full screen.
```
+-----------------------------------+
| artifact full width    [⤡ back]   |
|                                   |
+-----------------------------------+
```
- Strengths: needed for responsive HTML, video and PDF reading. The Claude iPad and Codex complaints both ask
  for it.
- Weakness for lfg: you lose the transcript, so it must be one tap back to the split, not a re-open.

### P6. Tabbed artifact pane / pane workspace
Used by: Claude Design tabs, VS Code editor groups, Claude Code desktop movable panes, GoodNotes tabs, Obsidian,
Codex "Diff | Logs".
```
+------------+----------------------+
| transcript | [a.md][b.png][c.pdf] |
|            | content of tab       |
+------------+----------------------+
```
- Strengths: you can compare and keep several artifacts open.
- Weakness for lfg: tab management is a desktop chore and costly on touch. lfg already has an ordered
  per-session file list, which gives the same reach with no state to manage.

### P7. Media index with "reveal in conversation"
Used by: Skype Gallery, hilos Files, Behance, Slack files, lfg's own Files & Links sheet. Gemini's tinted
card is the reverse link (pane to message).
```
+------------------+---------------+
| ...msg  [▣ card] | ◀ 3 / 12 ▶    |
| (card tinted)    | artifact      |
|                  | [Show in chat]|
+------------------+---------------+
```
- Strengths: answers "where did this come from" and "what else did the agent make". It fits an agent
  transcript, where files are scattered across hundreds of tool calls.
- Weakness for lfg: auto-scrolling the transcript to the source fights live follow mode. Make it a button,
  never automatic.

### P8. Open in new window (scene)
Used by: Mail compose, Notes pinch, GoodNotes "Open in New Window", Claude Code pop-out panes,
`QLPreviewSceneActivationConfiguration`.
```
+--------------+  +----------------+
| lfg window   |  | file window    |
+--------------+  +----------------+
```
- Strengths: true side-by-side across apps or Stage Manager. The system handles resizing.
- Weakness for lfg: the windows have no link (Mail's new window has no next/previous). Good as a secondary
  "Open in New Window" action, not as the main flow.

---

## 5. What this means for lfg

Opinionated. Each point names its evidence.

1. **Build P3 (co-equal split) as the landscape default. Do not build an inspector-width pane.**
   Tapping an artifact card or path in the transcript opens it in a trailing pane, and the transcript stays
   live. Evidence: Claude web, Gemini, Codex and Swift Playgrounds all do this. The Claude iPad 1/3-width pane
   is the documented failure (#100553). HIG iPadOS says to minimize "full-screen transitions".

2. **Default split: transcript 40%, artifact 60%. Divider snaps at three positions.**
   - On 11" landscape that is transcript about 478pt and artifact about 716pt. On 13" it is about 546 / 820.
   - lfg's transcript is designed for a phone (about 402pt), so it reads well at 40%. The artifact is what
     needs width. The Mobbin ratios cluster at 26–50% for the chat column.
   - Snap points: transcript at phone width (about 400pt), 40/60, and 50/50.
   - Make the divider a visible grab handle (Notability spacer, FCP handles). Tapping the handle toggles
     between 40/60 and full, like Logic's tap-to-max.
   - Dragging the artifact below about 320pt closes it. Dragging the transcript below about 320pt expands
     the artifact to full. Arc floors each pane at 15%, and HIG says keep the divider visible.
   - **Remember the last split per window.** Figma, Slide Over and the Codex #30703 request all point this
     way.

3. **Sidebar: hide it by a width rule, not by device. Restore it on close.**
   - When the pane opens, keep the sidebar only if the transcript stays ≥ 400pt *and* the artifact gets
     ≥ 600pt. Otherwise switch to `.detailOnly`.
   - In practice the sidebar hides on 11" landscape (1194 − 360 = 834pt, too little to split) and stays on
     13" landscape (1006pt left, about 402 / 604).
   - On close, put back whatever visibility the user had. WWDC25 208 says layout changes must be
     "non-destructive… revert back to the starting state".
   - Evidence: Claude and Gemini collapse the sidebar when an artifact opens. Slack and ChatGPT deep research
     keep it when there is room. HIG macOS says to auto-collapse the sidebar on resize.
   - If the user swipes the sidebar in while the pane is open on 11", let it *overlay*
     (`.prominentDetail`-like) instead of squeezing both columns.

4. **Multiple artifacts: one pane, replace on tap, page with ◀ ▶. No tabs in v1.**
   - Tapping another artifact in the transcript replaces the pane's content. Claude, Gemini and Linear peek
     all replace; none of them stack.
   - The pane pages through the existing `FilePreviewSequence` (session-wide Files & Links order). The header
     shows "3 / 12", with swipe or ◀ ▶, and ↑/↓ on a hardware keyboard like Linear peek.
   - A header menu lists all session files (P7). Skip tabs. They add state with no clear gain on touch, and
     lfg's ordered index already gives reach.
   - Revisit tabs only if Eugene compares two artifacts often. Then do Notability-style "pin and split", not
     browser tabs.

5. **Link back both ways (P7).**
   - Tint the transcript card whose file is open in the pane (Gemini). HIG says to "persistently highlight the
     current selection".
   - Put a "Show in conversation" button in the pane header (Skype). It scrolls the transcript to the source
     message and pauses live follow.
   - Never auto-scroll the transcript when the pane pages to another file. Follow mode is sacred in a live
     session.

6. **Close and expand: three states, each one tap away (P5).**
   - Pane header, trailing to leading: close (X), expand (⤢ goes full width, then ⤡ goes back), share, and a
     per-type mode toggle.
   - Full width hides the transcript and the sidebar, and ⤡ returns to the exact prior split (Swift
     Playgrounds Expand/Contract Canvas).
   - Keyboard: Esc closes, and Cmd+\ closes the focused pane (Claude Code desktop uses the same).
   - Do not use a trailing-edge swipe to close. It is too easy to fire while scrolling a PDF or panning an
     image. Dragging the divider to the edge does the same job.
   - Add "Open in New Window" in the overflow menu (P8, HIG Windows).

7. **Narrow fallback: below about 1000pt window width, use today's full-screen pager.**
   - The split needs at least 400 (transcript) + 1 + 560 (artifact). So it fits 13" portrait (1024pt, sidebar
     hidden) but not 11" portrait (834pt), Slide Over, or narrow Stage Manager windows.
   - There, tapping an artifact opens the existing `FileViewerSheet` full-screen pager. That is the
     inspector's "becomes a sheet when compact" behaviour, and what Claude iPhone does ("works well").
   - Decide by window width, not orientation (HIG Layout). If the window shrinks while the pane is open,
     hand the same item and index to the full-screen viewer. When it grows back, restore the split.

8. **Media chrome inside the pane (reuse the existing renderers):**
   - **HTML pages:** WKWebView at the pane's width. Expand is essential here, because responsive pages break
     at 700pt (#100553). Add a "Fit width / Actual width" toggle only if real pages need it.
   - **Markdown and code:** rendered by default, with a Rendered / Source toggle in the header. Claude
     Preview/Code, Gemini, Working Copy and VS Code all treat this as one pane with two modes.
   - **Images:** pinch and double-tap zoom inside the pane. Expand gives full-bleed.
   - **Video:** native AVPlayer controls inline. Support **Picture in Picture**, so closing the pane or
     scrolling the transcript keeps the clip playing (FCP for iPad, HIG Multitasking).
   - **PDF:** PDFKit continuous scroll at pane width, with a page indicator. No thumbnail rail at 60%; show
     it only in full width.

9. **Implementation stance (an opinion, not verified on device):**
   - Do not use SwiftUI `.inspector` for the artifact pane. Its sizing is designed for supplementary detail
     (Apple's example caps at 400pt). It has an iPadOS 26 sidebar-toggle bug when attached to the detail. On
     iPadOS 17 it fell back to an overlay at intermediate widths.
   - Two options, in order of preference:
     - (a) A custom two-pane container inside the existing detail column: an HStack plus a draggable 1pt
       divider with snap logic. The sidebar keeps its current `NavigationSplitView` behaviour.
     - (b) A UIKit `UISplitViewController` with the iPadOS 26 `.inspector` column, *if* a spike shows
       `preferredInspectorColumnWidthFraction` ≈ 0.6 works. It gives native drag-resize, the pointer cursor
       and the auto-sheet when compact.
   - Prototype (a) first. It keeps today's root navigation untouched.

**Open questions for Eugene** (none block a first prototype):
- Should the open artifact *follow* the agent? For example, auto-open a new file the session just wrote.
  Recommendation: no. Show a badge on the pane header ("2 new files"), don't swap content under him.
- Should the pane persist per session when switching sessions in the sidebar? Recommendation: yes, keep the
  last artifact per session. When he switches, close the pane unless the new session has one open.
