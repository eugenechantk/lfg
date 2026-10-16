# Self-check: session sheet round-1 fix, Subagents, Files & links (2026-10-16)

Same method as `phase3-menu-selfcheck`: app positions from the sheet's top edge, divided by 0.9602 (the iOS 26 inset sheet scale). Board sheet top: 200pt for both new boards. Board / app.

## Session sheet, verifier round 1 D1
- The subtitle now wraps like the board's CSS instead of truncating the host name.
- The Host value fits on one line at the right; when it is too long it wraps starting 10pt after "Host", left-aligned, and the row grows (board: 43 → 63pt). The doubled 20pt gap (a Spacer between two 10pt spacings) is gone from the Model, Effort and Host rows.
- Effort keeps the CLI names ("Medium") with the control given layout priority.

## Subagents (`s2-subagents`)

| Element | Board | App | Δ |
|---|---|---|---|
| Title glyphs / close button | 25.33 / 20.00 | 26.04 / 20.13 | +0.70 / +0.13 |
| Running dot | 105.00 | 105.19 | +0.19 |
| Row 1 title / Running / meta | 103.33 / 127.33 / 149.00 | 103.80 / 128.10 / 149.27 | ≤ +0.77 |
| Row 1 separator | 174.67 | 174.26 | −0.41 |
| Row pitch | 87.67 (render) / 88 (DOM) | 88.0 | 0 vs DOM |
| Row 4 failed line | 389.33 | 391.93 | +2.6 = 3 rows × the render's thin border (0.33) + row-1 offset |

## Files & links (`s2-files`)

| Element | Board | App | Δ |
|---|---|---|---|
| Title / close | 24.67 / 20.00 | 25.34 / 20.13 | ≤ +0.68 |
| Tab control / selected half / "Files 5" | 84.00 / 86.33 / 95.33 | 84.01 / 86.44 / 95.12 | ≤ 0.21 |
| Images header / first row icon / title | 145.33 / 182.00 / 175.67 | 144.76 / 181.91 / 176.01 | ≤ 0.57 |
| Videos header / video title | 291.33 / 322.33 | 290.91 / 322.85 | ≤ 0.52 |
| Documents header / last title / last meta | 380.00 / 469.00 / 490.33 | 379.78 / 470.04 / 491.22 | ≤ 1.04 |

Links tab: rows with a link mark, the link's title and "host · age".

## Known differences (not layout)
- Fixture data: the running subagent's time is live (the board's 1m 12s grows); files are listed newest first (the board's sections disagree with each other on order); link titles come from the existing link naming.
- System sheet chrome as before (inset at 96% scale, grabber, dim).
