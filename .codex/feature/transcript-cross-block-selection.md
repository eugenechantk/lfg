# Feature: Transcript Cross-Block Selection

## User Story

As an LFG iOS user, I want to drag a text selection across an assistant reply's paragraphs and list items so I can copy one continuous excerpt.

## User Flow

1. Open an assistant reply containing multiple paragraphs and a bulleted or numbered list.
2. Long-press within the reply to begin native text selection.
3. Drag a selection handle across paragraph and list-item boundaries.
4. Copy the selected range through the system edit menu.

## Success Criteria

- [x] SC1: One native selection can span separate paragraphs in the same assistant message.
- [x] SC2: The same selection can span paragraph-to-list and list-item boundaries.
- [x] SC3: Copy preserves the visible text, including list markers and line boundaries.
- [x] SC4: Existing inline styling, links, headings, code, tables, and transcript scrolling remain usable.
- [ ] SC5: The complete selection gesture passes independent Simulator verification. The independent auditor could not start because its fixed model is unavailable on this account; manual FlowDeck interaction verification passed.

## Test Strategy

- Extend the pure `SelectableText` coverage with a paragraph/list/paragraph fixture that pins document order, markers, and copied plain text.
- Run the focused `SelectableTextTests`, then the full LFGCore suite.
- Build and launch the existing `LFG_SELECT_TEXT_FIXTURE` through FlowDeck and record a real cross-block selection and copy/paste flow in Simulator.

## Tests

- `ios/LFGCore/Tests/LFGCoreTests/SelectableTextTests.swift`
  - `paragraphsAndListItemsFormOneCopyableDocument` — SC1-SC3 parser/copy contract.
- FlowDeck Simulator recording using `SelectTextFixture` — SC1-SC5 runtime behavior.

## Implementation Details

- Assistant prose will render as one non-scrolling `SelectableProseView` per message instead of one text view per Markdown block.
- The existing attributed renderer continues to own headings, inline styles, links, nested-list indentation, code-block decoration, and tables.
- User bubbles remain one plain-text selection surface as before.

## Verification

- Focused `SelectableTextTests`: 16 tests passed, including the new paragraph/list/paragraph copy contract.
- Full LFGCore suite: 593 XCTest cases passed (1 optional skip) and 183 Swift Testing cases passed.
- FlowDeck Debug build and launch passed on the isolated iPhone 17 Pro / iOS 26.5 Simulator.
- Runtime fixture: began with the word `steps`, dragged the lower native selection handle through the nested unordered list and both ordered-list items, then invoked the system Copy action.
- Copy/paste check: a separate runtime pass pasted `steps:\n•\tRestart the Air's serve…`, proving the clipboard crossed the paragraph/list boundary and retained the line break and bullet marker.
- Evidence: `.codex/evidence/20260924-transcript-cross-block-selection/cross-block-selection.mov`, `selection-crosses-paragraph-and-bullet.jpg`, and `selection-tree.json`.

## Residual Risks

- The required independent visual auditor could not run because `gpt-5.4` is unavailable on this ChatGPT account. Manual FlowDeck verification and captured interaction evidence cover the actual UIKit gesture.
- The installed FlowDeck build does not expose its documented `record` subcommand, so the interaction movie was assembled from FlowDeck's 250 ms UI-session frames at 2 fps. It proves state/gesture progression, not animation smoothness.

## Bugs

- Assistant Markdown currently creates a separate `UITextView` for every paragraph, list paragraph, table cell, and code block. UIKit selections cannot cross view boundaries.
