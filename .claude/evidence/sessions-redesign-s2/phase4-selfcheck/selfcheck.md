# Phase 4 self-check: desktop sessions list (2026-10-16)

Board `dA2-sessions` (400 × 860, rendered 1:1 in Chrome) against
`lfg --window-shot 400 <png> --height 860 --board` (this worktree's build, the board's sample data),
both 1x. The shot carries a Display P3 profile; `to_srgb.py` converts it before any colour is read.

## Geometry (`ink-measurements.txt`, board / app)

- Row separators: 82, 195, 270, 383, 458, 533, 646, 722 on both (534 in the app: the 75.3pt pitch).
- Every element is within 1pt, except two 1x rounding cases: "Air offline" starts 2pt right (the
  "Pro" label's width rounds up to a whole point, then the 12pt gap), and the Tasks label's thin
  "T" bar falls under the ink threshold (its bottom edge is +1).
- Title bar: switcher, badges and the round search button at the board's spots (the switcher sits
  12pt right of the window centre, between the window controls and the search button).

## Colour (sRGB)

| | Board | App |
|---|---|---|
| Window | (26,26,30) | (26,28,30) |
| Switcher track / picked segment | (46,46,50) / (85,85,88) | (47,46,50) / (85,85,88) |
| Search button / "By status" pill | (46,46,50) / (44,44,47) | (47,46,50) / (44,44,47) |
| Badge / Pro dot | (255,159,11) / (51,215,76) | same |
| Title / meta ink | (244,244,246) / (168,168,176) | (242,242,244) / (166,166,173) |
| Unpicked "Tasks" ink | (201,203,211) | (201,203,211) |

The translucent fills use the colours the canvas renders, not the CSS maths (Chrome draws white at
6–16% a few levels brighter). The off-screen shot draws the window inactive, so the title bar reads
(30,30,30) and the window controls grey; in a live, active window the title bar equals the list
surface ((25,25,28) both, screen capture).

## Behaviour

- **B12:** `listResumable` first page `total` — null on the first request, 3,982 after the
  background count (under 8s on the Pro); later pages omit it. Unit tests: `src/resumable-total.test.ts`.
- **DF5 (`df5-probe-output.txt`):** one process refreshes with the stub Air up, the stub is stopped,
  it refreshes again: Air goes `unreachable`, its live row stays (1) and is marked offline (1); the
  host strip shows "○ Air offline" (`app-live-air-offline.png`, real Pro data).
- **Live click:** this build run as its own window (isolated config, the real Pro): clicking the
  Recent header collapses it (chevron right, rows gone) and a second click brings it back
  (`live-click-collapse-recent.png`).
- **Live data:** folder names in the meta line come from the cwd ("inbox", "lfg", "fiftyworkout"),
  as on the phone; real Codex and Claude models read "Codex gpt-6-astra", "Claude Code opus".

## Tests

LFGCore 414 Swift Testing (incl. `DesktopSessionListTests`, 6) + 644 XCTest pass; desktop
feature tests 183 pass; `--window-fit 280 320 360 400 640` fits every width; bun 1234 pass
(2 known resumable-closed timeouts); iOS build green.
