# Feature: Restore Desktop Toolbar Actions

## User Story

As an LFG desktop user, I want the toolbar actions to use normal macOS control sizing and remain grouped on the right so the controls are legible and spatially consistent with the previous desktop layout.

## User Flow

1. Open the desktop session window at its minimum allowed width or wider.
2. Find Group, Refresh, Search, and Create together on the toolbar's trailing edge.
3. Use any action at standard macOS toolbar size without another action disappearing into overflow.

## Success Criteria

- [x] SC1: Group, Refresh, Search, and Create render at standard macOS toolbar control size. — **Verify by:** deterministic window snapshots at the minimum width and 900pt.
- [x] SC2: All four actions appear together on the trailing/right side, while host status remains leading/left. — **Verify by:** deterministic window snapshots and independent macOS visual audit.
- [x] SC3: No toolbar action overflows at any allowed window width. — **Verify by:** `--window-fit` at the measured minimum, compact threshold, and full width.
- [x] SC4: Create-session behavior and existing desktop behavior remain intact. — **Verify by:** complete `--desktop-feature-test` suite and clean desktop build.
- [x] SC5: The corrected bundle is installed and running on Pro and Air. — **Verify by:** matching installed executable hashes, signature validation, and installed-binary feature tests on both hosts.

## Test Strategy

- Capture the current minimum-width toolbar as failing visual evidence before editing.
- Use the real off-screen AppKit window harness to measure toolbar fit rather than inferring it from source dimensions.
- Run the existing 128-assertion headless suite for behavioral regression coverage.
- Use an independent visual auditor for final placement and sizing evidence.

## Tests

- `desktop/build/lfg.app/Contents/MacOS/lfg --window-fit <minimum> 820 900` — SC3.
- `desktop/build/lfg.app/Contents/MacOS/lfg --window-shot <minimum> ...` — SC1, SC2.
- `desktop/build/lfg.app/Contents/MacOS/lfg --desktop-feature-test` — SC4.

## Implementation Details

- Restore each action as a normal `.primaryAction` toolbar item.
- Remove `.mini` control sizing and the compact leading action cluster.
- Raise the root minimum width to the smallest measured width that keeps every standard-size trailing action visible.

## Decision Log

- Prefer a slightly wider minimum window over shrinking or relocating primary actions; toolbar legibility and stable placement are more valuable than retaining a 440pt window that cannot fit the requested controls.

## Verification Evidence

| Criterion | Result | Evidence |
|---|---|---|
| SC1 | PASS | `.claude/evidence/20260902-110946-verification-audit/04-after-568.png` and `05-after-900.png`; compact action widths are 35–36pt. |
| SC2 | PASS | Independent audit confirms host status left and all four actions trailing/right at 568pt and 900pt. |
| SC3 | PASS | `03-window-fit.log`: `fits:true`, `dropped:[]` at 568, 600, 700, 819, 820, and 900pt. |
| SC4 | PASS | Fresh build succeeded; `02-desktop-feature-test.log` reports 128/128 passing assertions. |
| SC5 | PASS | Commit `8066b3c` was built and signed in an isolated worktree. Pro and Air both run `/Applications/lfg.app` with SHA-256 `28b2f5ed03273ba30ce788be518c8efc9ce3d97299bd3c67761df04f50955571`; the installed binary reports 128/128 passing assertions on each host. |

Independent audit: **PASS** — `.claude/evidence/20260902-110946-verification-audit/evidence.md`.

## Residual Risks

- None. Previous installed bundles remain recoverable in each Mac's Trash.

## Bugs

_None yet._
