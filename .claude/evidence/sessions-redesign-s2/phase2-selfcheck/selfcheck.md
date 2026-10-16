# Phase 2 self-check before the verifier (2026-10-16)

Method: board specs from the DOM (`specs/*.txt`), boards rendered at 3x in Chrome (CSS zoom 3, stitched tiles), app frames from simulator recordings (3x). The same script (`appmeasure.py`) measures both images: colour runs for box edges, glyph rows for text. Values in points, written board / app.

| Board | Check | Board | App | Δ |
|---|---|---|---|---|
| 1 s2-view | Bubble bottom → next prose glyph | 19.33 | 19.33 | 0 |
| 1 | Prose → "Read 6 files" step (glyph tops) | 37.67 | 38.33 | +0.67 |
| 1 | Step → prose line 1 / prose line pitch | 36.33 / 24 | 36.67 / 24 | +0.33 / 0 |
| 1 | "Edited 2 files" and pills, from the composer top | — | — | ≤ 0.67 |
| 2 s2-tools-group | Card height | 231.33 | 231.67 | +0.33 |
| 2 | FILE / input / RESULT / output line 1 / Show all, from card top | 10.33 / 30.0 / 73.33 / 100.67 / 210.67 | 10.33 / 30.0 / 73.33 / 101.33 / 211.0 | ≤ 0.67 |
| 2 | Input line 2 (17pt line) | 47.0 | 48.0 | +1.0 |
| 2 | Header → first call row / row pitch | 31.0 / 27.67 | 30.67 / 28.0 | −0.33 / +0.33 |
| 2 | Prose → header | 35.67 | 38.33 | +2.67 (board conflict A: +2) |
| 3 s2-tools-single | Card height | 267 | 268 | +1.0 |
| 3 | COMMAND / input / "In ~" / OUTPUT / 8 output lines / Show all, from card top | 10.33 / 30.0 / 52.33 / 76.67 / … / 246.0 | 10.33 / 30.33 / 52.67 / 77.0 / ≤ +1.0 / 246.67 | ≤ 1.0 |
| 3 | Row glyph → card top | 25.3 | 25.0 | −0.3 |
| 5 s2-queued-failed | Bubble height / bubble → prose | 40 / 19.33 | 39.67 / 19.33 | ≤ 0.33 |
| 6 s2-question | Bubble → step | 15.0 | 16.67 | +1.67 (conflict A: +2) |
| 6 | Step → prose line 1 | 32.33 | 36.67 | +4.33 (conflicts A + B: +4) |
| 7 s2-signin-prompt | Bubble → step | 17.33 | 17.33 | 0 |
| 7 | Step → prose line 1 | 34.0 | 36.0 | +2.0 (conflict B: +2) |

Boards 4 and 5's strip, menu, composer and panels passed verifier round 9 and have not changed since.

## Board conflicts (the app follows `s2-view`)
- **A. Gap between transcript items:** 14pt on `s2-view`, `s2-signin-prompt`, `s2-queued*`; 12pt on `s2-question`, `s2-tools-group`, `s2-tools-single`.
- **B. Step row padding:** `s2-view` and `s2-tools-*` give the step row 2pt above and below; `s2-question` and `s2-signin-prompt` draw it with none.

## Fixes made during the self-check
- Prose half-leading tried and reverted (it cascaded through calibrated offsets); kept the measured layout.
- 1.67pt under user bubbles (boards 1, 5, 7 now exact).
- Card input on its 17pt CSS line box (`cssLineBox`, monospaced).
- Card top padding back to 10pt (round 9 D1).
