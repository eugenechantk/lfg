# Retry later: colour decision

**Decision: Retry later uses the same tokens as every other Tasks screen, with no scoped colour overrides.** Light mode keeps the system colours; dark mode keeps the board values. I corrected the light reference boards so they draw what those tokens render. App code doesn't change for the accent or the failed card. Two light-mode idle fills need a token fix (section 3).

- **Canvas:** https://claude.ai/artifact/F2B1MNbv5oxuscm237M9sD, version **`1792297149-cc18` (Version 81)**, page "Retry later (Oct 18)".
- **Persistence check:** a fresh read matched all 16 Retry later boards byte for byte with `reference/project/`. The other 147 boards and all 8 pages are unchanged.
- **Boards changed in v81:**
  - `rl-phone-failed`, `rl-phone-minutes`, `rl-phone-time`, `rl-phone-pending`, `rl-mac-sheet`: light tokens only. Every light wrapper renders through these.
  - New board `rl-phone-invalid-light`: the invalid state in light, states row, x 2360.
  - The `rlRules` note gained one line on light colours.
- **Dark values:** unchanged in every board.

## 1. Accent: keep the system accent (no fixed fill)

- `TaskColors.accent` and `accentFill` are `adaptive(light: .accentColor, dark: <board hex>)`. The type's comment says "The boards' dark-mode tokens. Light mode keeps the system colors." That is the pattern the shipped Tasks screens use: the list, task view, edit form and chat all render the system blue in light mode.
- The `#0A6EE0` in my v80 light boards was copied from the older light canvas boards (`tA2-*`). Those boards were never the light spec the app implemented; A2 dark became the direction, and light mode kept system colours.
- A fixed fill only for Retry later would make its blue differ from the Retry now button on the same card. So I corrected the reference, not the token.
- **Light values now drawn:**
  - iOS: `#0088FF`, as measured on iOS 26.3.
  - Mac: `.accentColor` resolves to `controlAccentColor`, `#007AFF` at the default accent. I measured it with `NSColor` in aqua on macOS 26. Mac `systemBlue` is `#0088FF`, but `.accentColor` follows the user's accent setting.
- **Dark (unchanged):** `#0A6EE0` fill and `#409CFF` text on the phone; `#3B8EFF` and `#8FB8FF` on the Mac.

## 2. Failed card: keep the shared tint

- `TaskStatusCard` tints its fill with `TaskColors.danger`:
  - iOS: `tintOpacity` 0.17, no border, both themes.
  - Mac: 0.08 with a 0.28 border.
- In light mode, `danger` is `.red`, which is `#FF383C` on iOS and macOS 26. 17% of that over white is `#FFDEDE`, which matches the verifier's `#FFDDDE` for the existing app within rounding.
- The v80 board's `#FFF0F0` was 8% of the old canvas red: the older light board's value, not the token's. Retry later changes nothing about the failed card except its third action, so the shared token stays.
- The v81 board draws `rgba(255,56,60,0.17)`. The divider above the footnote uses the existing `tint.opacity(0.25)`. The label and icon are `.red`, not the old darker board red.
- **Mac light:** `rgba(255,56,60,0.08)` with a 0.28 border, which is the existing Mac token.
- **Dark:** unchanged. The board's 16% matches the A2 dark board, which earlier rounds already passed; the code's 17% stays.

## 3. Idle fills in light mode: a token clarification (app fix needed)

**Problem.** Two light-mode surfaces use grouped backgrounds on a card that is already white:
- the unpicked chip (`tertiarySystemGroupedBackground`);
- the disabled confirm capsule.

Both render white on white, so the verifier saw the invalid capsule vanish. iOS's own pickers in the same card take their idle fill from the fill colours, not the backgrounds. That covers the compact date and time pickers and the segmented track.

**Decision.** Every idle control fill in the Retry later sheet uses one adaptive token:

```
idle fill  light: Color(.tertiarySystemFill)   // rgba(118,118,128,0.12): #EFEFF0 on the white card, #E3E3E9 on the #F2F2F7 sheet
           dark:  #3A3A3C                       // unchanged: the board's chip and disabled fill (= elevated tertiarySystemGroupedBackground)
```

Applies to:
- unpicked minute chips (`TaskChipButtonStyle(unselectedFill:)`);
- the disabled "Retry later" capsule;
- the date and time pills if drawn by hand.

The native segmented control and compact `DatePicker` already use it.

- **Disabled capsule label:** `Color(.systemGray)` (`#8E8E93`) in both themes; the capsule shape stays.
- **Picked chip:** `TaskColors.accentFill` with white text (section 1).
- **Mac:** keeps `TaskPalette.control` (`.primary` at 10%, `#E9E9E9` in light), which is already visible on the Mac card. No change.
- **Recommendation:** name it once, for example `TaskPalette.idleFill` on iOS, and use it as `TaskChipButtonStyle`'s default unselected fill. The edit form's frequency chips use the same default (`TaskPalette.control`, white in light), so they likely have the same white-on-white problem in light. That is outside Retry later's scope; Codex can decide whether to batch it.

## 4. The rest of the light translation (board values for the verifier)

All of these are existing tokens, as they render on iOS 26 / macOS 26 in light:

| Token | iOS light | Mac light |
|---|---|---|
| `TaskColors.grey` (`.secondary`) | `#8A8A8E` on white | `#808080` |
| `TaskColors.soft` (`.primary` at 82%) | `#2E2E2E` | `#4D4D4D` |
| `TaskColors.ink` | `#000000` | `#262626` |
| `TaskColors.danger`, `dangerLabel` (`.red`) | `#FF383C` | `#FF383C` |
| `TaskColors.success` (`.green`) | `#34C759` | — |
| rail (`.primary` at 20%) / upcoming node (`.secondary` at 70%) | `#CCCCCC` / `#ADADB0` | — |
| sheet / card | `#F2F2F7` / `#FFFFFF` (grouped backgrounds) | page `#FFFFFF`, card `TaskPalette.card` `#EFEFEF` |
| `TaskPalette.field` + `accentFill` border | `#FFFFFF` + `#0088FF` | `#F4F4F4` + `#007AFF` |
| neutral status card (`TaskPalette.card`) / its secondary button (`TaskPalette.control`) | `#F2F2F7` / `#FFFFFF` | — |

The iOS greys come from UIKit's published light values (`secondaryLabel` = rgba(60,60,67,0.6)); I couldn't measure them on device here. The accent (Codex's iOS 26.3 measurement) and the Mac values (measured with `NSColor`) are the measured ones.

## For Codex

1. **No code changes for the accent or the failed card:** keep `TaskColors.accentFill` and `accent`, and keep `TaskStatusCard.tintOpacity`.
2. **Change the idle fill:** unpicked chips and the disabled confirm capsule use the idle fill from section 3, light `tertiarySystemFill` and dark `#3A3A3C`, with a `systemGray` label on the disabled capsule.
3. **Resume the frozen comparison** against v81 (`reference/project/*.dc.html` are its exact sources; `gen_boards.py` regenerates them).
