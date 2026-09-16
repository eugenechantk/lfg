# Feature: in-place native text selection in the transcript (v3: per block, original rendering)

_(File keeps its original name `select-text-sheet.md`; the sheet approach in
v1 was rejected — see Decision Log.)_

## User Story

As an lfg user reading a transcript on iPhone, I want to long-press a word in
an assistant response (or a user bubble, or a table cell), get the native
cursor + magnifier, drag to extend the highlight, and copy exactly that range —
the same gesture the composer's text field already gives me.

## Background

`ProseView` (MarkdownUI) rendered each paragraph and table cell as its own
SwiftUI `Text`; on iOS that supports "long-press → Copy the whole block" and
nothing finer. v1 (2026-09-06 afternoon) answered with a long-press menu and a
"Select Text" sheet; Eugene: "You did it completely wrong. I need to be able to
do the native thing and long press to get a cursor, and drag to highlight. Like
how I can do that now in my input field."

## User Flow (v3)

1. Long-press a word anywhere in an assistant reply or a user bubble.
2. The word highlights with the native selection overlay: two drag handles and
   the edit menu (Copy · Look Up · Translate · Share …).
3. Drag a handle to extend within that block — a paragraph, a list item's
   paragraph, a code block, or ONE table cell. Dragging past the block's edge
   clamps at its last character. (Eugene, v2 review: "Revert back to the
   original rendering, but let me long press and highlight text, but limited
   to the content of that cell. We don't need cross cell copying.")
4. Tap Copy. Tap elsewhere to clear. A plain swipe still scrolls the transcript.
5. Rendering is MarkdownUI's `lfgFlat` theme exactly as before v2: bordered,
   horizontally scrolling tables; GitHub code-block chrome; quote bar; lists.

## Success Criteria

- [x] SC1 (re-verify v3): Long-pressing a word in an assistant reply, on the transcript itself,
  shows the native selection overlay (highlight, two handles, edit menu with
  Copy). — **Verify by:** simulator recording on the fixture and on a live
  transcript row.
- [x] SC2 (v3): Dragging a handle inside a table cell extends within the cell
  and clamps at the cell's edge; Copy puts exactly that range on the
  pasteboard. — **Verify by:** recording + pasteboard read.
- [x] SC3 (re-verify v3): Markdown structure is preserved in the native view: heading, bold,
  inline code, link, bulleted + nested bullet, numbered list, fenced code block
  with a box, blockquote. — **Verify by:** `SelectableTextTests` + screenshot.
- [x] SC4 (v3): Tables, code blocks, lists (incl. nested), quotes and headings
  render exactly as MarkdownUI did before v2 — bordered, horizontally
  scrolling table with semibold header; code box; bullets centred on the
  first line of an item even when it holds a nested list. — **Verify by:**
  screenshot compared with `.claude/feature/evidence/select-text-sheet/03-…`
  (pre-v2 rendering) and `v3/05-original-rendering-restored.jpg`.
- [x] SC5 (re-verify v3): User bubbles use the same native view (white text on accent), hug
  their content width, keep tap-to-show-timestamp, and support long-press
  selection. — **Verify by:** recording.
- [x] SC6 (re-verify v3): A plain vertical swipe over a reply scrolls the transcript rather
  than selecting. — **Verify by:** recording on a transcript taller than the
  screen.
- [x] SC7 (re-verify v3): Tapping a link in a reply opens it (no crash, no selection). —
  **Verify by:** tap `runbook` in the fixture; Safari/URL handler opens.
- [x] SC8 (re-verify v3): Plain text with no markdown renders unchanged. — **Verify by:**
  `SelectableTextTests.plainTextIsOneParagraph`.

## Platform & Stack

- iOS 17.2+, Swift 6, SwiftUI + UIKit (`UITextView`, TextKit 2 for decoration
  drawing), Foundation `AttributedString(markdown:)` `.full`, LFGCore (SPM).

## Tests

### Package Unit — `ios/LFGCore/Tests/LFGCoreTests/SelectableTextTests.swift`
15 tests pinning the block model (paragraph/heading/list/code/quote/table/rule,
inline styles, links, soft/hard breaks, ragged tables, fallback). Unchanged
from v1 — the parser is reused.

### App target
`SelectableProseView`, `ProseTextView` and `SelectableTextRenderer` are UIKit
and are proven in the simulator (no app-target unit test host exists).

## Implementation (v3)

- `ios/LFG/RichContent.swift` — `Theme.lfgFlat` overrides `.paragraph`,
  `.codeBlock` and `.tableCell` to render `configuration.content` through
  `SelectableProseView` (one native `UITextView` per block) while keeping
  MarkdownUI's layout; `.listItem` gets `TopAlignedListItemLabelStyle`
  because a UIKit view has no text baseline and the default `Label` style
  centred bullets on the whole item. `ProseView` is the transcript renderer
  again.
- `ios/LFG/SelectableProse.swift` — `SelectableProseView` gains `.code`
  content (mono, unwrapped, hugs width) and `semibold:`; fonts follow the
  GitHub theme (16pt, 0.85em code, 0.25em line spacing); unspecified-width
  proposals answer with the natural width so MarkdownUI's table cell
  `Layout` can measure. The v2 whole-message table/code drawing in
  `ProseTextView` is unused by the transcript now and can be deleted later.
- `ios/LFG/Components.swift` — assistant branch back to `ProseView(text:)`;
  user bubble keeps `SelectableProseView(plain:)`.

## Implementation (v2, superseded)

- `ios/LFG/SelectableProse.swift`
  - `SelectableProseView` — `UIViewRepresentable` around a non-scrolling
    `ProseTextView`; `sizeThatFits` answers SwiftUI's width proposal with the
    laid-out height (and the natural width when `hugsContent`); memoised
    render keyed on (content, palette, width); link taps go to SwiftUI's
    `openURL`; optional `onTap` for chrome that used to hang off
    `.onTapGesture`.
  - `ProseTextView` — `UITextView` subclass drawing table fills/gridlines and
    code-block boxes in `draw(_:)` from custom attributes
    (`lfg.blockKind`, `lfg.tableWidth`, `lfg.tableRowIndex`, `lfg.blockID`),
    using TextKit 2 layout fragments.
  - `SelectableTextRenderer` — blocks → `NSAttributedString`; `Palette`
    (`.standard` / `.onAccent`); table columns measured and scaled to the
    available width.
  - `SelectTextFixture` (DEBUG, `LFG_SELECT_TEXT_FIXTURE=1`).
- `ios/LFG/Components.swift` — `TextBubble` assistant branch uses
  `SelectableProseView(markdown:)`; user branch uses
  `SelectableProseView(plain:palette:.onAccent, hugsContent:true, onTap:)`.
- `ios/LFG/RichContent.swift` — `ProseView` (MarkdownUI) is no longer used by
  the transcript; kept for `MarkdownTableLayoutFixture` and any other caller.
- Removed: `SelectableTextSheet.swift` (v1 sheet + context menu).

## Decision Log

- **v3: per-block native text views inside MarkdownUI, not a whole-message
  renderer.** Eugene rejected v2's table rendering and dropped the cross-cell
  requirement. MarkdownUI's block styles expose each block's markdown
  (`configuration.content`), so each paragraph/cell/code block hosts its own
  `UITextView`; layout, borders, scrolling and spacing are MarkdownUI's own.
  Selection is scoped to the block by construction.
- **List markers top-aligned via a `LabelStyle`.** MarkdownUI's
  baseline-centred `BulletItemStyle` is visionOS-only; on iOS the default
  `Label` style is used, and an `alignmentGuide(.firstTextBaseline)` on the
  representable had no effect (verified with a `d[.top]` experiment). The
  `.listItem` hook receives the whole `Label`, so a custom style with
  `HStack(alignment: .top)` plus an icon offset of half a line height centres
  the marker on the first line.

- **v1 sheet rejected → in-place `UITextView` per message.** Only a UIKit text
  view gives the long-press cursor/magnifier/handles on iOS; MarkdownUI's
  blocks are separate SwiftUI `Text`s and its block model is internal, so the
  transcript row now renders through my own attributed-string renderer.
  MarkdownUI stays in the tree (fixture, other callers) but the transcript no
  longer uses it. Trade-offs accepted: tables wrap inside the message width
  instead of scrolling horizontally; images were already stripped to cards.
- **Table grid drawn by the text view, not by TextKit.** iOS has no
  `NSTextTable`; rows are tab-stop paragraphs and `ProseTextView.draw` paints
  fills and hairlines under them so they still read as a table while staying
  one selectable run.
- **User bubbles are plain, not markdown.** A user typing `*` or `#` must not
  get formatting.
- **Decided earlier (still true):** Foundation markdown parser for structure;
  parsing lives in LFGCore for `swift test`; pbxproj is regenerated by
  `xcodegen generate` (project.yml is the source of truth; fastlane
  regenerates on deploy anyway).

## Verification Evidence

Self-verification 2026-09-06 22:26–22:28 HKT on simulator
`C926BFC6-0395-445D-AF67-CFB3061961BF` (iPhone 17 Pro, iOS 26.3), fixture
`LFG_SELECT_TEXT_FIXTURE=1`, screenshots in `.claude/feature/evidence/select-text-sheet/v2/`:
long-press "healthy" in the table → handles + Copy menu; handle drag extended the
highlight across the row, "Next steps:" and two list items
(`02-inplace-drag-across-table-and-list.jpg`); Copy → paste into the fixture field
pasted the range starting "degraded" (`03-inplace-copy-pasted.jpg`); user bubble
hugs its text and a tap shows the sent time (`04-…jpg`).

**Independent audit (ios_visual_evidence_auditor): PASS**, report
`.claude/evidence/20260906-222930-ios-visual-audit-v2/evidence.md`. SC1 also on a
live transcript row; SC2 highlight matched the pasteboard byte-for-byte via the
Mac pasteboard the simulator syncs; SC5 tap + long-press on the bubble; SC6 swipe
scrolled a long live transcript with no selection; SC7 link opened Safari and the
app survived. LFGCore: 137 tests passing (15 for the parser).

## Deployment

- **TestFlight build 202609062312** (v3), train 1.3.0, uploaded 2026-09-06
  23:14 HKT after the v3 audit PASS; `verify_testflight_build` DoD PASS 23:16
  (VALID, highest train, internal=IN_BETA_TESTING). Logs
  `ios/fastlane/deploy-202609062312.log`, `ios/fastlane/verify-202609062312.log`;
  tree snapshot `.claude/feature/evidence/select-text-sheet/v3/deploy-202609062312-tree.patch`.
  Supersedes 202609062249 (v2) and 202609062213 (v1).

- **TestFlight build 202609062249**, train 1.3.0, uploaded 2026-09-06 22:51 HKT
  from the working tree after the v2 audit PASS. `verify_testflight_build`
  DoD PASS at 22:53 (VALID, highest train, internal=IN_BETA_TESTING). Logs:
  `ios/fastlane/deploy-202609062249.log`, `ios/fastlane/verify-202609062249.log`;
  tree snapshot `.claude/feature/evidence/select-text-sheet/v2/deploy-202609062249-tree.patch`.
  Supersedes 202609062213 (v1 sheet).

## Verification Evidence (v3)

Self-verification 2026-09-06 ~23:00 HKT, sim `C926BFC6-…`, fixture; screenshots
`.claude/feature/evidence/select-text-sheet/v3/`: cell long-press on the original
table (`01`), handle dragged past the cell edge clamps at "pro" (`02`), original
rendering restored with bullets on the first line (`05`), paragraph long-press (`06`).
**Independent audit PASS**: `.claude/evidence/20260906-230538-ios-visual-audit-v3/evidence.md` —
SC2 pasteboard read back exactly `macbook-pro`; table and code box scroll
horizontally; live transcript swipe scrolls and long-press selects; link opens
Safari; 15/15 parser tests.

## Residual Risks

- Paste INTO an app field on a real device is the only half of SC2 not proven
  (the simulator's paste callout never inserts); the pasteboard contents were.
- Wide tables wrap within the message width instead of scrolling horizontally.
- Not checked: iPad, Dark Mode, Dynamic Type at large sizes, very long replies'
  layout cost (one UITextView per row, memoised render).

## Bugs

_None open._

## History

- v3 (this build): original MarkdownUI rendering restored; native selection
  per paragraph / cell / code block.

- v1 (TestFlight build 202609062213): long-press menu + "Select Text" sheet.
  Rejected by Eugene on sight. Superseded by v2 in this doc.
