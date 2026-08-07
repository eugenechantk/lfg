# Feature: Desktop Menu-Bar Quick Access

## User Story

As an lfg desktop user, I want a compact menu-bar window showing sessions that need input, sessions that are running, and my most recent other sessions so I can jump back into the right terminal without finding the main app window.

## User Flow

1. Launch the existing lfg desktop app.
2. Click the lfg status item in the macOS menu bar.
3. Review de-duplicated Needs Input, Running, and Recent sections in a compact window.
4. Click a session to use the existing iTerm2 attach/resume behavior.
5. Use Open All Sessions to reveal the main desktop window when more context is needed.

## Success Criteria

- [x] SC1: The desktop app exposes a native menu-bar item whose window displays Needs Input, Running, and Recent session sections from the shared store. — **Verify by:** headless menu-bar snapshot plus live macOS AX/screenshot audit.
- [x] SC2: Needs Input uses the server's current prompt state and outranks paused/working classification. — **Verify by:** Bun journal-state test and `--desktop-feature-test` precedence assertions.
- [x] SC3: Sessions are sorted deterministically, do not repeat between sections, and each section is capped for a compact panel. — **Verify by:** `--desktop-feature-test` projection assertions.
- [x] SC4: Clicking a session uses the existing `Opener.open` path; Open All Sessions reveals the single main window. — **Verify by:** code-path assertion plus live macOS AX audit without opening a real session.
- [x] SC5: Menu-bar and main-window refreshes share one store and do not overlap network refreshes. — **Verify by:** build plus `--desktop-feature-test` refresh/projection coverage.

## Test Strategy

- Extend the single-file app's existing headless feature-test hook for classification, sorting, de-duplication, and caps.
- Add a focused Bun test for retrieving the latest prompt presence from the server journal.
- Render a deterministic off-screen menu-bar fixture for visual inspection.
- Run the built app and use cursor-free macOS accessibility/screenshot inspection for scene wiring and layout.

## Tests

- `desktop/LFGSessions.swift`
  - Needs Input outranks blocked and busy.
  - Running excludes Needs Input.
  - Recent excludes Needs Input/Running, sorts by activity, and respects its cap.
  - Section counts retain the uncapped totals.
- `src/journal.test.ts`
  - Latest prompt presence follows prompt set, update, and clear events.

## Implementation Details

- Add a lightweight `GET /api/session-states` response sourced from journaled prompt state rather than re-scraping every tmux pane per desktop refresh.
- Decode the response opportunistically so older hosts still provide Running and Recent sections.
- Add `MenuBarSessionProjection` as the pure presentation seam.
- Add `MenuBarExtra` with `.window` style beside a single-instance main `Window` scene.
- Keep the existing 10-second refresh cadence; `SessionStore.refresh` rejects overlapping refreshes.

## Decision Log

- Keep Needs Input distinct from Paused. `status == blocked` represents upstream failures; prompt presence is the actionable question signal.
- Exclude Needs Input and Running rows from Recent to avoid wasting compact-panel space on duplicates.
- Cap Needs Input and Running at four rows each and Recent at five; section headers retain full counts and Open All Sessions exposes the complete list.
- Reuse the desktop app's existing attach/resume opener rather than introduce deep links or a second launch mechanism.
- Derive the 18 pt template icon from the canonical transparent lfg logo at build time; preserve the exact brand geometry and let macOS provide light/dark tinting.

## Residual Risks

- Final menu-bar status-item interaction may require real HID input if macOS Accessibility cannot press the system status item; that escalation requires explicit approval.

## Verification Evidence

| Criterion | Evidence |
| --- | --- |
| SC1 | `--menu-bar-snapshot` rendered all three sections; live AXPress opened one 380×530 pt menu window. See `.codex/evidence/menu-bar-quick-access/menu-bar-popover.png`, `live-menu-window.png`, and `live-menu-tree.json`. |
| SC2 | `src/journal.test.ts` passed latest prompt set/update/clear coverage; `--desktop-feature-test` passed prompt-over-blocked/busy precedence. |
| SC3 | `--desktop-feature-test` passed ordering, de-duplication, uncapped counts, and 4/4/5 cap assertions. |
| SC4 | Live AX tree contains enabled session-row buttons and `menu_bar_open_all_button`; source routes rows through `Opener.open` and footer through `openWindow(id: "sessions")`. No real session was opened during verification. |
| SC5 | Both scenes share the app-owned `SessionStore`; build passed and `refresh()` now rejects overlapping work. |

Full command ledger: `.codex/evidence/menu-bar-quick-access/evidence.md`.

Independent verdict: **PASS** — `.codex/evidence/20260807-133709-verification-audit/evidence.md`.

## Bugs

_None yet._
