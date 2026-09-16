# Feature: Readable Markdown Tables

## User Story

As an LFG user reading agent output, I want Markdown table columns to stay within a readable width range so that dense tables are legible without long cell content stretching columns indefinitely.

## User Flow

1. Open a session or Markdown attachment containing a table.
2. Read short cells without columns collapsing into narrow stacks of words.
3. Read long cells wrapped across lines once a column reaches its maximum width.
4. Swipe horizontally when the bounded columns still make the table wider than the viewport.

## Success Criteria

- [x] SC1: Every rendered Markdown table column has a readable content-width range of 140–280 points. — **Verify by:** simulator screenshot and accessibility frames for short and long columns.
- [x] SC2: Long cell content wraps after the column reaches 280 points instead of extending on one line. — **Verify by:** simulator screenshot showing a long cell on multiple lines.
- [x] SC3: Tables wider than the transcript viewport retain their bounded column widths and can be scrolled horizontally. — **Verify by:** simulator interaction showing content at both the leading and trailing edges.
- [x] SC4: Table headers, row backgrounds, borders, padding, and surrounding spacing remain visually distinct. — **Verify by:** simulator screenshot and independent visual audit.
- [x] SC5: The iOS app compiles with the shared Markdown theme applied to transcript prose and Markdown file previews. — **Verify by:** `flowdeck build`.
- [x] SC6: A table row grows to the height of its tallest wrapped cell even when that cell is not in the first column. — **Verify by:** simulator screenshot of a row whose later cell wraps to at least three lines, with the next row beginning below all wrapped text.
- [x] SC7: Row backgrounds and borders remain aligned with the expanded row, with no text overlapping a later row. — **Verify by:** simulator screenshot of the same regression fixture plus accessibility frames for cells in the affected and following rows.

## Test Strategy

This is a visual-only SwiftUI theme change with no state or transformation logic to unit test honestly. Compilation verifies the MarkdownUI API contract; Simulator evidence verifies sizing, styling, and horizontal scrolling.

## Tests

- FlowDeck build of the LFG scheme — SC5.
- Simulator table fixture with long prose, static screenshot and accessibility frames — SC1, SC2, and SC4.
- Simulator horizontal swipe across the fixture — SC3.
- Simulator regression fixture with a short first cell and a three-line later cell — SC6 and SC7.
- Independent iOS visual evidence audit — SC1–SC4 and SC6–SC7.

## Implementation Details

- Centralize table styling in `MarkdownUI.Theme.lfgFlat` so transcript prose and Markdown attachment previews share it.
- Give each table cell a 140-point minimum and 280-point maximum content width before horizontal padding.
- Measure each cell label using the final bounded width so Markdown wraps before SwiftUI Grid fixes the row track height.
- Preserve the existing horizontal `ScrollView` behavior and restore explicit GitHub-like borders, alternating row backgrounds, and table margins.

## Decision Log

- Use a per-cell minimum rather than a minimum width for the whole table. This directly prevents one short column from being compressed while another consumes the available width.
- Use 140 points of content width (166 points including horizontal padding). Two columns remain comfortable on common phone widths; three or more columns naturally scroll.
- Cap content width at 280 points (306 points including padding). This is wide enough for scanning medium values while forcing prose, paths, and long identifiers to wrap.
- Apply the style in the shared theme instead of only `ProseView`, so file previews do not regress to compressed tables.
- Replace the flexible frame with a small custom `Layout`. It preserves content-driven column widths but measures height using the final bounded width, which a plain frame cannot guarantee during Grid's ideal-size pass.
- Keep an environment-gated DEBUG fixture in the app. It makes this visual regression reproducible without depending on a live host, a particular transcript, or database setup.

## Residual Risks

None identified. Compilation and deterministic Swift tests cannot prove this SwiftUI Grid behavior, but the DEBUG fixture and independent Simulator audit now cover the regression directly.

## Verification Evidence

- SC1–SC5 — Independent visual audit PASS under `.codex/evidence/20260830-222552-ios-visual-audit/`. `02-leading-edge.*` shows 167-point and 307-point column strides, plus a long value wrapped to a 272×42-point frame. `03-trailing-edge.*` shows the rightmost column moved onscreen after a horizontal swipe.
- SC5 — `flowdeck build --json` from `ios/`: `BUILD succeeded` on 2026-08-30 using scheme `LFG` after reordering the width cap ahead of `fixedSize`.
- Runtime audit launch — `flowdeck run -S 134CEB2C-3B06-4C2E-A546-EA4444145013 --json`: build, install, and launch succeeded for `com.eugenechan.lfg`.
- SC1–SC4 and SC6–SC7 — Independent visual audit PASS under `.codex/evidence/20260905-190421-ios-visual-audit/`. The later cell measured `277×58.33` points across three lines; its bottom was `y=346.33`, while the following row began at `y=359.33`. A horizontal swipe moved the table content 105 points without changing row geometry.
- SC5 — `flowdeck build --json` and the fixture's isolated `flowdeck run` both completed with `BUILD succeeded` on 2026-09-05.

## Bugs

- Resolved: a flexible frame reported a one-line ideal height to Grid when a later cell contained the longest value. `BoundedTableCellLayout` now measures the label at the final capped width before reporting the cell height, so the shared row track expands before drawing.
