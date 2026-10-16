# Sessions list (phone) vs canvas board `s2-list` — verification round 5

**Verdict: PASS.** Every in-scope component matches the board within 2pt and within a few RGB levels. The product owner accepted the remaining differences ahead of time. Four sub-2pt observations and one app-only polish note are listed below. None of them blocks the board match.

- **Design ground truth:** `http://127.0.0.1:8793/s2-list.dc.html`, rendered in Chrome (new tab), artboard 390×844 at the top-left. Geometry comes from `getBoundingClientRect`, and colours come from the source file `scratchpad/dcrender/project/s2-list.dc.html`. Folded and expanded states were rendered by clicking the board's own headers. The board's list container clips at 844pt, so lower states were captured by scrolling it with `scrollTop`; a temporary 150px spacer let the last rows clear the dock. The 3x crops came from CSS `zoom: 3` tiles (`raw/d05_default_3x_partial.png`; magenta marks areas not captured).
- **App:** iPhone 17 Pro sim `C47EB72F-…`, fixture `LFG_S2_LIST_FIXTURE=1` and `=taskbadge`, relaunched with `flowdeck run --no-build` (same build). Frames are the last frame of a 1s h264 recording at 3x (1206×2622).
- **Coordinates:** the app sits about 4pt lower than the board at the top (top-bar centre 84 vs 80) because the iPhone 17 Pro status bar is taller. The offset shrinks to about 3pt down the list. All comparisons below have this global offset removed.

## Per-component results

| Component / state | Internal consistency | Structure | Copy | Typography | Colour | Glyphs | Spacing / shape | Result |
|---|---|---|---|---|---|---|---|---|
| Header: host chips | PASS, uniform black bg | PASS | PASS | PASS (16 semibold; cap height 12 vs 11.7) | dots #30D158 vs #2ED057 | PASS (8pt dots) | dot x 16, text 31 (both); Air dot 69 vs 68 | PASS |
| Header: search/more capsule | PASS | PASS | n/a | n/a | glass (accepted) | search 16×16 both; ellipsis 16×4 vs 15.4×3.4 | right inset 16 vs 17.5; height and spacing set by system (accepted) | PASS |
| Section headers (open) | PASS (see O3) | chevron, label, count, action | PASS | 15 semibold label / 15 regular count | label #A1A1A6 vs #A1A1A4; count #8E8E93 vs #8D8D8D–#909090; amber #FF9F0B vs #FE9A0A | chevron-down 13pt, stroke 3; ink 7×5 vs 8.4×5 | 38pt tall in both; chevron x 20–23, label x 42 | PASS |
| Section headers (folded) | PASS | chevron-right, no action, no rows | PASS | PASS | PASS | chevron-right 5×7 at x 24 (both) | 38pt pitch; 17.5pt below the separator (both) | PASS |
| Needs input: question row | PASS | dot / title / ask line / meta | PASS | title 17 semibold, line 15, meta 13 | dot #FF9F0B vs #FC9E09; line amber matches | ask bubble matches the path (8x crop) | dot 20..28, title x 41, glyph 12×11 vs 11×10.4, line text x 59 (both) | PASS |
| Needs input: sign-in row | PASS | PASS | PASS | PASS | PASS | key glyph matches (8x crop) | PASS | PASS |
| Working rows (incl. task row) | PASS | live dot + "Working · Nm" + meta | PASS | title 17 regular | green #30D158 vs #2CD157 | live dot: core 7pt, halo 13 vs 12.3pt; repeat glyph matches (8x) | text after dot x 53 vs 53.3 | PASS |
| Unread rows (incl. task row) + Mark all read | PASS | PASS | PASS (order and "5h" are data / accepted) | title 17 semibold; "New reply" #D1D1D6 vs #D2D2D4 | purple #BF5AF0 vs #BE58EE; action #409CFF vs #419AFE | PASS | Mark-all-read right inset 16 vs 17.3 (O2) | PASS |
| Unread folded | PASS | "Mark all read" hidden, chevron-right (same rule as the board) | — | — | — | — | — | PASS |
| Idle row | PASS | PASS | PASS | regular 17 / 15 / 13 | dot #0A84FF vs #0582FF; line #A1A1A6 vs #A4A4A4 | PASS | every line within 1pt of the board after the offset | PASS |
| Closed row | PASS | no host (accepted) | PASS | PASS | dot #636366 vs #626262 | PASS | within 1pt | PASS |
| Load more (app-only, accepted) | NOTE (O5) | only under an expanded Closed group; absent when Closed is folded (a07) | "Load more" / "Loading more" | 15 regular | #3C93F0 | chevron-in-circle / spinner | label x 49.0 idle vs 43.3 loading | PASS (note) |
| Dock pill | PASS (glass accepted) | Sessions (selected) + Tasks | PASS | labels 10 semibold; "Sessions" 43 vs 43.0pt wide | selected highlight #3A3A3C vs #37373A; Sessions blue #409CFF | Sessions glyph 22.3×17.7 vs 22.3×17.3; Tasks glyph about 18×17 (both) | pill x 20..~205, y bottom-28, h 56 (both); highlight 40.7 vs 40.3pt tall at x=35 | PASS |
| Dock badges | PASS | Sessions "2" in both fixtures; Tasks "1" only in the taskbadge fixture (data) | PASS | 11 bold | #FF9F0A, 18×18 | — | Sessions badge x 74.3 vs 74.0, 8pt from dock top (both); Tasks badge x 160.3 vs 162.0 (O1) | PASS |
| Plus button | PASS | PASS | — | — | glass (accepted) | plus 14.7×14.7, centred (both) | 56×56, right 20, bottom 28 (both) | PASS |
| Whole screen: fixed header and dock while scrolling | — | header and dock hold position while rows scroll under them (a02–a04) | — | — | scroll-edge fade top and bottom (accepted; see O3) | — | header-to-first-section gap 55.5 vs 56 | PASS |
| Default fold state | — | the code defaults to Idle and Closed folded, like the board (`collapsedByDefault`) | — | — | — | — | — | PASS (by source + persisted state) |

## Deltas and observations (all non-blocking)

- **O1 — Tasks badge:** about 1.7pt further right. Design x 160.3..178.3, app 162.0..180.0. The Sessions badge matches exactly.
- **O2 — "Mark all read":** right inset 16pt in the design vs 17.3pt in the app. Text side bearing explains part of this.
- **O3 — Needs input header:** about 7% dimmer at rest (chevron #9B9B9B vs #A7A7A7 on the other headers; design #A1A1A6 on all). The code gives every chevron the same token, and the dimming repeats in a01 and a08. A scrolled frame (a07) shows a graded top fade: a title at y≈127 drops to 80%, and text below y≈150 is at 100%. This header sits at y 132–147, inside the tail of that fade. This falls under the accepted scroll-edge fade. The same fade dims the folded Closed header above the dock when the list is at the bottom (#898989 vs #A2A2A5).
- **O4 — Row rhythm:** rows are 87.67pt vs 88pt. Inside a row, the second and third lines sit about 0.7pt lower relative to the title. Separators are 2 device px (#2C2C2C) vs a 0.5pt hairline (#2C2C2E), and both start at x=40. Meta and count greys are neutral (#8F8F8F–#909090) vs the board's #8E8E93; the blue-channel difference is 3–5 levels. All of this is below what the eye can see.
- **O5 — Load more (app-only):** the "Loading more" state is steady across the full 1s clip (`app_loading_more_frames.png`). Its label starts 5.7pt further left than "Load more" (x 43.3 vs 49.0), so the label jumps sideways when paging starts. The label also dims to about 50%, and the spinner is nearly invisible on black (peak #353535). The design has no counterpart, so this is a polish note, not a board delta.

## Accepted, excluded from judgement

Glass capsule, dock and plus button; capsule height and spacing; closed rows without host; scroll-edge fades; raw model names; the Load more row; relative times ("5h" instead of "9:00 AM"); SF text about 6% narrower than Chrome (title widths 152 vs 161, 175.7 vs 185); data differences (counts 15/17/40 vs 3/1/1, Unread order, Tasks badge count, the repeat glyph on the "Ship" row in the taskbadge fixture).

## Not verified, and side effects

- The default fold state on a fresh install was verified from source (`SessionListSection.collapsedByDefault` returns idle or closed), not by deleting the stored key. At launch the app showed Idle open because a persisted `["closed"]` was stored. I left it at `["closed"]` again.
- A mis-tap while restoring that state opened the "Liquid Glass tab bar" session detail. I went straight back; nothing was typed or sent. The fixture still shows the row as unread. The prefs plist now holds `lfg.lastSeenMessageID` entries for the `s2fx-*` fixture ids. The entries cover non-unread rows too, so the app may write them on its own. The visible unread state is unchanged.
- No iPad check, because adaptive chrome was out of scope.

## Files

- **Paired crops (design left, app right):** `pair_full_top.png`, `pair_header_3x.png`, `pair_needs_input_3x.png`, `pair_working_3x.png`, `pair_unread_2x.png`, `pair_lower_idle_closed_open.png`, `pair_lower_folded.png`, `pair_dock_default.png`, `pair_dock_tabs_taskbadge_4x.png`, `glyphs_8x.png`
- **App-only:** `app_loadmore_states.png` (left = loading, right = idle; the tool's header labels read DESIGN/APP but both crops are from the app), `app_loading_more_frames.png`
- **Raw:** design `raw/d01_default_1x.png`, `raw/d02_idle_closed_open_1x.png`, `raw/d03_idle_folded_closed_open_1x.png`, `raw/d04_both_folded_1x.png`, `raw/d05_default_3x_partial.png`. App: `raw/a01` (top), `raw/a02`/`a03` (bottom, Idle open, Closed folded), `raw/a04` (Closed open, Loading more), `raw/a05` (both open, Load more), `raw/a06` (Idle folded, Closed open), `raw/a07` (both folded), `raw/a08` (relaunch), `raw/a09` (Unread folded), `raw/b01` (taskbadge).
