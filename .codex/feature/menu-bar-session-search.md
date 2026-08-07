# Feature: Menu-Bar Session Search

## User Story

As an lfg desktop user, I want to search sessions directly in the menu-bar window so that I can open the right session without switching to the full desktop window.

## User Flow

1. Open the lfg menu-bar window.
2. Type into the search field below the status header.
3. See Needs Input, Running, and Recent filter immediately while preserving their existing grouping and ordering.
4. Open a matching session, clear the query to restore all sessions, or see a clear no-results state.

## Success Criteria

- [x] SC1: The menu-bar window exposes a focused, automation-addressable search field labeled “Search sessions.” — **Verify by:** installed-app AX inspection for `menu_bar_search_field`.
- [x] SC2: Search is case-insensitive, ignores surrounding whitespace, and matches the existing title, project, last message, model, agent, and host fields across all three menu sections. — **Verify by:** desktop feature CLI filtering tests.
- [x] SC3: Filtered sessions retain the existing section precedence, ordering, counts, and per-section limits. — **Verify by:** desktop feature CLI projection tests.
- [x] SC4: A non-empty query with no matches shows “No matching sessions”; clearing the query restores the unfiltered list. — **Verify by:** installed-app AX interaction and state assertions.
- [x] SC5: The compact menu-bar window renders cleanly with the search field and remains scrollable at its maximum height. — **Verify by:** snapshot plus installed-app screenshot/audit.

## Test Strategy

- Extend the single-file desktop feature CLI because this standalone SwiftUI target has no Xcode test bundle.
- Test the pure search-to-projection seam independently of SwiftUI rendering.
- Use AXDriver against the installed app for focus, typing, empty-state, and clear-query behavior.

## Tests

- `desktop/LFGSessions.swift` / `DesktopFeatureTestCLI`
  - Search matches fields case-insensitively after trimming.
  - Search filters Needs Input, Running, and Recent without changing their ordering.
  - Empty queries restore every input item.
- Installed app
  - `menu_bar_search_field` exists.
  - A unique query produces the expected row or empty state.
  - Clearing restores sections.

## Implementation Details

- Query state belongs locally to `MenuBarQuickAccessView` as `@State`.
- A pure `MenuBarSessionProjection(items:query:)` seam reuses `SessionSearch.matches` before applying grouping, ordering, counts, and limits.
- Search is local and synchronous; no debounce or network request is needed.

## Decision Log

- Use a compact plain `TextField` with a magnifying-glass affordance instead of `.searchable`, because this is a `MenuBarExtra` window rather than a toolbar and needs deterministic width.
- Reuse the desktop window’s existing `SessionSearch` contract so both surfaces search the same fields.

## Verification Evidence

- SC1: AXDriver found `menu_bar_search_field` as an enabled `AXTextField` in the installed `/Applications/lfg.app` menu-bar window.
- SC2–SC3: `desktop/build/lfg.app/Contents/MacOS/lfg --desktop-feature-test` returned `{"ok":true,"tests":37}`. The added cases cover trimmed/case-insensitive filtering across Needs Input, Running, and Recent, filtered counts, and empty-query restoration.
- SC4: AXDriver typed `computer froze`; the reopened menu showed exactly the matching session. A nonmatching query exposed `menu_bar_search_empty_state`, and pressing `menu_bar_search_clear_button` restored six visible session rows with an empty field value.
- SC5: `--menu-bar-snapshot /tmp/lfg-menu-bar-search-v3.png` rendered a clean 380-point search layout. The installed app screenshot `/tmp/lfg-menu-search-match.png` shows the live dark-mode match state; the maximum live window measured 380×527 points.
- Install: the built and installed executable SHA-256 values both equal `0d6d7bbc14ab62bd2ac678cb0ea2978ed676f060e14c9ee040e035011e171675`; `codesign --verify --deep --strict` passed.
- Independent audit: **PASS** for SC1–SC5. Report and durable screenshots/AX evidence: `.claude/evidence/20260807-144617-verification-audit/evidence.md`.

## Residual Risks

None known. AX text entry, matching, no-results, clearing, compact sizing, and installed-bundle identity were exercised on the live app.

## Bugs

- Fixed during implementation: AppKit text inputs render as an invalid yellow control under off-screen `ImageRenderer`. Snapshot mode now substitutes a noninteractive, visually equivalent placeholder while the installed app retains the real search field.
