# Self-check before verifier round 3 (2026-10-16)

Board / app, in points. Full-screen pages and the full-height sign-in sheet sit 8pt
lower in the app because the iPhone 17 Pro's top inset is 62pt (the board's is 54).
Positions below are relative to the page or sheet top.

## Sign-in browser (`s2-signin`, `LFG_S2_VIEW_FIXTURE=signin` → "Sign in on iPhone")

| Element | Board | App (before) | App (after) |
|---|---|---|---|
| Top bar buttons, 40pt, from the sheet top | 13 | 13 | 13 |
| Address pill width | 274 on 390 | 286 on 402 | 286 |
| Pill: host line ink top / purpose ink top (from pill top) | 8.33 / 24.33 | 7.33 / 25.0 | 8.0 / 23.67 |
| Lock ink top | 9.33 | 8.67 | 9.33 |
| Page edge → "I'm signed in" top | 10.67 | 2.67 | 11.33 |
| Capsule bottom → screen bottom | 31 | 31.3 | 31.3 |

Fixes:
- The host line had a 1pt gap and SwiftUI's taller line under it; now no gap and a 16pt line box.
- The bottom bar sat right under the page; the board has 8pt of sheet between them.
- The fixture's "No login cookies yet" line pushed the top bar down; the login phase now shows its error under the bar.
- The review title named the host by its URL ("lfg-air.eugenechantk.me"); it now uses the same name as the address pill.

Review step (SC11, fixture): two debug-only cookies (example.com, example.org) → "I'm signed in" →
"Send this sign-in to Mac?", example.com on, example.org off, "Send 1 cookie" → switch example.org on →
"Send 2 cookies" (`review-1-cookie.png`, `review-2-cookies.png`). Send was not tapped (it would reach a
real host). A synthetic tap does not flip a Form toggle; a raw touch down/up does.

## Terminal (`s2-terminal`, scratch rig, shell switched to `sh`)

| Element | Board | App |
|---|---|---|
| Close button 44pt, from the page top | 4 | 4 |
| Title ink top / subtitle ink top (from button top) | 8.0 / 27.67 | 8.0 / 27.67 |
| Fit/Wide pill, x / width / right margin | 286 / 92 / 12 | 298 / 92 / 12 |
| Fit segment / "Wide" label centre in its half | 44 / centred | 44 / centred |
| Close and pill fill | (49,49,50) rendered | (38,38,40) → (47,47,49) |
| Output inset left / right / top | 12 / 12 / 10 | 0 / 0 / 0 → 12 / 12 / 10 |
| Output → key row | 10 | 12 (whole terminal rows; the remainder falls at the bottom) |
| Key row: bar / key height / key top in bar | 50 / 36 / 7.33 | 50 / 35.67 / 7.33 |
| Keys: esc / tab / ctrl / others, gap | 43.7 / 43.3 / 51.7 / 40, 6 | 44 / 44 / 53 / 40, 6 |

Fixes: the header fills use the colour the canvas draws (#313132; the CSS asks for white at 12% over
#0B0B0D, which SwiftUI blends to #28282A); the output got the board's insets.

Accepted: Chrome draws the board's `ui-monospace` keys in Menlo Bold (small solid arrows, a curled
"l"); the app uses SF Mono Semibold as the CSS declares, so esc/tab/ctrl come out 0.3–1.3pt wider and
the arrows larger. The board shows the software keyboard; the simulator has a hardware keyboard, so
the key row sits at the screen bottom.

Live (scratch rig): the key row scrolls when a swipe starts on a key, without firing it; ⌘V pastes.

## Round-2 sheet fixes

- Session sheet, long host (`board-menu-longhost-3x.png` from round 2): tile grid board 96.3 / app 96.5;
  second tile row 182.3 / 182.6; card 1 275.0 / 274.9; its rows 316.7 / 316.6, 365.0 / 364.9,
  428.0 / 428.4, 470.7 / 470.7; card 2 528.0 / 527.7; card 2 bottom 611.0 / 609.6 (board row pitch).
- Links tab against the DOM spec (sheet coordinates, top 200): tile 20,147.5–50,177.5 / 20.1,147.9–50.0,177.7;
  letter centred (162.5 / 162.5); title ink top 148.2 in a 144 line box; arrow ink 360.8–372.3 (path
  maths 360.8–372.2); separators 192.5 / 192.7 and 253.5 / 253.6.
- Subagents separators: 1–2 device pixels on both, pitch 87.3 render / 88 app.
