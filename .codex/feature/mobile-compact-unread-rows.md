# Compact unread session rows

Product tier. iPhone session list.

## User story

Unread rows show the title and metadata without a redundant New reply line. Keep their unread emphasis and dot, the same row height as working rows, and the compact centered layout used by idle and closed rows.

## Success criteria

- [x] Unread rows show two adjacent lines with no New reply text or empty middle slot.
- [x] The two-line group is vertically centered, with its dot aligned to the title. Unread title emphasis stays visible.
- [x] Unread, working, idle, and closed rows retain equal height. Working retains its useful status line.
- [x] Existing row tests, simulator build, and independent light/dark visual audit pass.

## Implementation and verification

Extend SessionRow's existing compact presentation to the unread group. Keep the shared line resolver and desktop presentation unchanged. Add an unread row with a stable ID to the existing network-free SessionListTimeFixture.

This small layout change needs no new unit tests that mirror the view structure. Run the existing SessionListRow suites, then measure the rendered rows on iPhone in light and dark appearance.

## Evidence

- Existing SessionListRow suites: 18 tests passed in four suites. Log: `.codex/evidence/20261016-compact-unread-rows/tests.log`.
- FlowDeck build and launch passed on iPhone 17 Pro / iOS 26.3. Log: `.codex/evidence/20261016-compact-unread-rows/build-run.log`.
- Parent light appearance check: unread accessibility content contains only its title and metadata; the merged text frame is 40 points tall, matching idle and closed. All four section starts have equal 101.67-point pitch. Unread title is visually emphasized and the purple dot follows its title. Screenshot and tree: `self-light.jpg` and `self-light-tree.json` in the evidence directory.
- Independent visual audit: PASS on iPhone 17 Pro / iOS 26.3 in light and dark appearance. Report: `.codex/evidence/20261016-213651-ios-visual-audit/evidence.md`. All four section pitches measure 101.67 points, with text centers 57.17 points from each section start. The unread dot/title centers differ by 2 points. The emphasized title and purple dot remain visible, with no clipped text.

## Residual risks

Physical devices and other OS versions were not tested. Release status is tracked separately from this feature audit.
