# Feature: Preserve Table Rendering With Cross-Block Selection

## User Story

As an LFG iOS user, I want assistant prose and bullet lists to remain continuously selectable without flattening Markdown tables into the message-wide text renderer.

## User Flow

1. Open an assistant reply containing prose, bullet points, and a Markdown table.
2. Drag a native selection across prose and bullet-item boundaries within a prose section.
3. Read and horizontally scroll the table using the original MarkdownUI grid layout.
4. Select text inside one table cell when needed; selection does not need to cross cells.

## Success Criteria

- [x] SC1: Adjacent prose paragraphs and list items remain one native selection surface.
- [x] SC2: Markdown tables render through the existing MarkdownUI grid with bounded cells, borders, alternating rows, and horizontal scrolling.
- [x] SC3: Each table cell remains independently selectable; selection does not need to cross table-cell boundaries.
- [x] SC4: Prose before and after a table remains visible, ordered, and selectable within its own contiguous section.
- [x] SC5: Fenced code containing pipe/delimiter-looking lines is not misclassified as a table.
- [x] SC6: A table followed by prose has the same 16-point bottom spacing as a normal paragraph; a table at the end of a message adds no extra trailing section padding.

## Test Strategy

- Add pure Swift tests for splitting an assistant Markdown message into contiguous selectable prose sections and isolated table sections.
- Cover prose/list/table/prose ordering, multiple tables, tables at message boundaries, and false positives inside fenced code.
- Run the focused tests, the full LFGCore suite, a FlowDeck build, and Simulator visual verification using the existing table fixture.

## Tests

- `ios/LFGCore/Tests/LFGCoreTests/SelectableMarkdownSectionsTests.swift`
  - prose and list stay in one selectable section — SC1
  - table is isolated between prose sections — SC2-SC4
  - multiple and boundary tables preserve ordering — SC2-SC4
  - fenced code containing table syntax stays prose — SC5
- FlowDeck Simulator table fixture — SC2-SC4 runtime rendering.

## Implementation Details

- Segment raw assistant Markdown only at complete GFM pipe-table blocks outside fenced code.
- Render prose sections with the whole-section `SelectableProseView`.
- Render table sections with `MarkdownUI` and the existing `.lfgFlat` theme, which already gives each table cell its own selectable text view.
- Apply the same 16-point external section spacing after a table that is followed by another section; do not add trailing padding when the table ends the message.

## Verification

- Focused `SelectableMarkdownSectionsTests`: 7 tests passed.
- Full LFGCore suite: XCTest and 190 Swift Testing cases passed.
- FlowDeck Debug build and fixture launch passed on the isolated `cc-01a0d1b9` Simulator.
- The table fixture visibly restored the two-column grid, bounded/wrapped cells, borders, alternating backgrounds, and correct row height.
- A FlowDeck horizontal swipe moved the table content while surrounding prose remained fixed.
- Independent visual audit: PASS. Evidence is in `.codex/evidence/20260924-180253-ios-visual-audit/`.
- Table-spacing follow-up: FlowDeck fixture geometry kept the table unchanged and moved the following prose from `y=433` to `y=449`, proving the requested 16-point bottom gap.
- Independent table-spacing audit: PASS. Evidence is in `.codex/evidence/20260924-185432-ios-visual-audit/`.

## Residual Risks

- A selection gesture cannot cross a table boundary by design; the user explicitly requires only prose/list cross-block selection and per-cell table selection.
- The fenced-code false-positive case is covered by deterministic tests rather than a dedicated visual fixture.
- The existing visual fixture does not end with a table; zero trailing padding for that branch is enforced by the compiled `followedByAnotherSection ? 16 : 0` conditional.

## Bugs

- The cross-paragraph implementation routed the entire assistant message, including tables, through the custom single `UITextView`; that preserved selection but replaced the original MarkdownUI table grid.
