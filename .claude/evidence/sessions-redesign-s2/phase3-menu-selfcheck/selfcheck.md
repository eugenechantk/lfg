# Session sheet self-check before the verifier (2026-10-16)

Board `s2-menu` (3x render in Chrome) against the app's `LFG_S2_VIEW_FIXTURE=menu` frame (3x, h264 last frame). Script: `measure_menu.py`.

## The system draws a partial-height sheet at 96% scale

iOS 26 insets a partial-height sheet by scaling it: the visible sheet is 386pt wide on the 402pt screen, 8pt in from each side, with rounded bottom corners. Everything inside scales with it: the 20pt badge measures 19.3 × 19.0, rows 41 instead of 43, tiles 113.3 instead of 118. So every app position is converted back before comparing: `y = (y_app − sheet top) / 0.9602`. This is the accepted system sheet chrome.

## Positions (unscaled, from the sheet's top edge; board / app)

| Element | Board | App | Δ |
|---|---|---|---|
| Pencil and close buttons | 20.33 | 20.13 | −0.20 |
| Terminal icon / label | 109.67 / 150.67 | 109.70 / 150.66 | ≤ 0.03 |
| Files badge | 106.00 | 105.53 | −0.47 |
| Model text / Claude mark | 288.67 / 286.33 | 288.48 / 286.05 | ≤ 0.28 |
| Effort control / selected segment | 324.67 / 327.00 | 324.93 / 327.01 | ≤ 0.26 |
| Fork icon / text | 421.33 / 422.33 | 422.13 / 423.52 | +0.80 / +1.19 |
| Unread dot | 467.00 | 468.65 | +1.65 (board threshold catches the antialiased edge; DOM dot top 468.5) |
| Stop row / End icon | 521.67 / 563.33 | 522.80 / 564.46 | +1.1 |
| Footer | 608.67 | 609.59 | +0.93 |

The ~1pt from the Fork row down: the board's 3x render draws its 1px separators thin, so its rows pitch 42.67 against the DOM's 43; the app follows the DOM (rows 386 / 429 / 478 / 521 / 564).

Horizontal insets (unscaled): tile label 29.00 / 28.81, row text 33.67 / 33.67, effort control from right 31.67 / 31.94, chevron from right 34.67 / 35.41, Fork text 62.00 / 61.79.

## Colours (dominant ink, board / app)

Tile icon blue 65,156,255 / 63,154,251; tile labels 242,242,247 / 240,240,243; row labels 255 / 252; values 161,161,166 / 161,161,164; Fork blue 65,156,255 / 63,154,255; End red 255,69,59 / 255,68,61; selected segment 99,99,102 / 97,97,100; chevron 72,72,74 / 69,69,72; separator 52,52,54 / 52,52,54; footer 161,161,166 / 160,160,162. All within video tolerance.

## Fixed during the self-check

- The close button sat 20pt from the right; the board puts it 16pt (in line with the cards).
- The subtitle used SF's 16.7pt line; the board's is 16pt (moved everything below by 0.7pt).
- A long host name ("Eugenes-MacBook-Pro") truncated the subtitle mid-path and squeezed "Host" onto two lines. The host name now gives way first, and the Host row keeps "move to …" readable.

## Known content differences (not layout)

- Host names are the real ones ("Eugenes-MacBook-Pro", Air is "Mac"); the board says "Pro" / "Air".
- The fixture session id is `s2fx-fork`, not `7f3a…c21`.
- The fixture has no browser preview, so that tile is dimmed (the board shows one).
- Effort segments use the CLI names ("Medium"), as decided for the model chip in Phase 2.
- iOS SF text is 2–8% narrower than the board's Chrome render (iOS applies SF tracking: −0.43pt per character at 17pt).
