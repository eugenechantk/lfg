# Usage limits: independent visual verification

**PASS — final visual scope and explicit carryovers below.** No confirmed visual mismatch remains. The independent iOS runtime audit also reports PASS.

## Scope and provenance

I independently rendered the approved standalone HTML, captured and operated the actual Mac app, and inspected the other independent auditor's original iPhone/iPad captures. No application source was edited by this verifier.

Reference: `.codex/design/account-usage-limits/preview/index.html`, Canvas version 87 design rules in `design.md`. Headless Chromium rendered the original HTML at 1280 × 1000, zoom 1, with loaded system fonts and explicit theme/scenario controls. Renderer details are in `renderer.json`. Computed bounds and styles are in `round-1/reference-*-all-dom.json` and later round folders. The local canvas exports refer to an absent support.js; the supplied standalone preview is the rendered reference. No reference was repaired or approximated.

| Original reference | SHA-256 |
|---|---|
| preview/index.html | 4d39ebbd76e0bd815f1deb731de8368f3fdad66994a05b7ee0e84d16907b8d11 |
| design.md | f0baf5ce0b487fedd975a14eddedc01358b97b2b6b562a5f70c73a11798477ce |
| reference/scenarios.js | 843352ae2cfa5bab68911d25e0a477190a54a22d23cff1721b7a9a81509d2f4a |

Mac: dedicated bundle com.eugenechan.lfg.usage-audit, using the real shared/desktop/Core sources, isolated Pro/Air fixture on 8987. It showed No sessions. FlowDeck build/run logs are retained. Final round-3 executable hash: cd21ef4ef800dfe2dfabd4cdd47e715d466d550b9c812674a6f63e1e3424d608. Loaded debug-code dylib hash: 369692dff4fef6b0245b36203db869b71dd4621c930c10332af8f720699b2789. Final shared-view source hash: f1050c28f2efd2ea6b9055716c68d1b2a3badd3dd9731dfde0b4abe485f625b1.

Mac PNGs isolate the actual attached popover through the parent-supplied CoreGraphics window capture. They are 346 pixels wide, matching AX's 346-point outer frame; this includes 26 points of native chrome around 320-point content. Original monitor ICC profiles are preserved. Measurements convert to sRGB before comparison.

iOS originals and AX trees: `.codex/evidence/20261020-235132-ios-visual-audit/`. They are 402 × 874 iPhone and 834 × 1210 iPad JPEG exports. Small exact-colour claims cannot rely on these compressed images. The final debug-code dylib hash is 795431ceb8137955f4e05e3e5bb7a02f7b653e61a2a70a19709543f9f7cd5499. The independent iOS auditor's report records its isolated simulator identities, build route and complete flow recording.

## Final rechecks and findings

- **F2 resolved:** the red error outline appears in fresh Mac light/dark and final iPhone/iPad captures. Rounded corners remain coherent.
- **F3 resolved:** Try again now has a native toned capsule surface. Mac uses a compact 24-point visual button; phone uses the approved visual pill with its larger touch target. AX exposes the action separately.
- **F4 resolved:** actual fixture shutdown now produces faded cards, explicit offline copy and last-reading provenance while preserving numbers. I stopped only Bun 75915 on 8987, refreshed the actual Mac app, captured both cards by scrolling, then restored the fixture. Mac proof: `round-3/mac-offline-light.png`, `mac-offline-scrolled-light.png` and matching trees. iPhone proof: `35-iphone-offline-retained-ultimate-final.jpg`; recovery: `36-iphone-retry-recovered-ultimate-final.jpg`. Both visibly match the offline treatment. The Mac surface changes from sRGB 239 to about 245; post-composited pixels cannot establish an exact decimal opacity, but the fade matches the reference's computed 0.58.
- **F1 withdrawn:** an initial inference about heavier Mac quota labels was too specific. Control measurements show similar native/Chromium glyph-density differences for semibold plans, regular identity text and quota labels, while text advances match. This is covered by the approved native-font translation. It does not justify forcing a lighter native font.

Earlier reports remain unchanged in `round-1/evidence.md` and `round-2/evidence.md`.

Fresh final-source rechecks cover Mac normal/error/offline light and final iPhone normal/error/offline/recovery light, plus final iPad error presentation. iOS files 31, 32, 33, 35 and 36 were inspected independently. Mac final-source normal and error cards and all four quota rows have fresh paired crops in round 3.

Explicit carryovers: normal dark and error dark from Mac round 2; phone true dark from file 16; Accessibility XL and its scrolled/bottom states from files 17–19; weekly-only correction from file 20 and the corrected Mac weekly capture; identity, API billing and refresh states from round 1. These precede the scoped iOS connection-error mapping and final offline plural copy. Their unchanged visual components retain their named build/capture scope; they are not presented as new captures of those states.

## Measured matches and exceptions

- Normal Mac cards: reference 290 × 212.95 CSS pixels, native 292 × 206 points. Native content fitting is explicitly allowed. The system popover width/chrome is treated separately from its 320-point content.
- Mac surfaces match after profile conversion: #232327/#FFFFFF grounds and #26262B/#EFEFEF cards. Normal fills match #3B8EFF dark and approximately #007AFF light. See round-1/colour-samples.json.
- iPad form sheet is 460 points wide with 420-point cards. Its preview scales a 1210-point mock to 918 display pixels; the measured 318.64-pixel reference card represents 420 logical CSS pixels. Native height fitting keeps content reachable.
- Phone headers preserve Close leading, centred title and Refresh trailing. Provider, identity, quota, reset and provenance order matches. Bars remain thin; percentages align with labels.
- Missing synthetic windows show Not reported without a duration, bar or track. API billing has no invented quota. Unidentified accounts stay separate and explain why. Runtime account labels, hosts, dates and equivalent shorter notices are valid content differences.
- Used up is red and full. Little left is amber and labelled. Stale data preserves normal number opacity; actual offline cards use the separate dimmed treatment. Error cards keep available readings below their notice.
- The Mac preview's global .bar CSS adds padding inside tracks. Native bars correctly use the reported percentage; that web-only artifact is excluded from literal matching. The SAMPLE tag is omitted in live UI.
- Native sheets, menus, popover chrome, system fonts and fitted line heights are accepted translations. No arbitrary pixel tolerance was introduced. A hosting-page sticky TOC may overlap the mock's top; component crops exclude that page chrome.

## Runtime checks and limits

Mac AXShowMenu and AXPress open the actual destination. The iPhone menu order is Terminal → Usage limits → Settings. Mac uses its existing host-strip menu. Refresh preserves numbers, disables its action and shows a spinner/Refreshing footers. Scroll captures show content moving beneath the pinned header. Both offline cards, their provenance and the account footnote remain reachable. Escape removed the popover from AX.

The iOS auditor recorded the complete final flow in `37-core-flow-refresh-retention-ultimate-final.mov` and dismissed state 38. Its final report is PASS. I independently inspected the final stills; I do not claim a second independent playback review of that recording.

**Separate keyboard limit:** pid-targeted Command-R injection did not establish a refresh in the background AX session. A physical-key shortcut and complete focus-order/VoiceOver speech audit remain unverified. This is outside the visual verdict; it is neither reported as a successful shortcut nor treated as a proven UI defect.

## Component matrix

Each row covers internal consistency, layout, copy, typography, colour, glyphs, spacing/shape, state and navigation chrome. PASS uses the explicit native exceptions above. N/A means no glyph or navigation chrome exists within that isolated component; full screens cover shared chrome. R1 rows are the documented baseline/carryovers; R3 rows are fresh final rechecks. Every pair was inspected, including native-resolution crops for uncertain detail.

| Component/state | Consistency | Layout | Copy | Type | Colour | Glyphs | Spacing | State | Chrome |
|---|---|---|---|---|---|---|---|---|---|
| R1 mac-dark-card-0 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 mac-dark-card-1 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 mac-dark-row-0 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 mac-dark-row-1 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 mac-dark-row-2 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 mac-dark-row-3 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 mac-dark-header | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| R1 mac-light-card-0 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 mac-light-card-1 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 mac-light-row-0 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 mac-light-row-1 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 mac-light-row-2 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 mac-light-row-3 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 mac-light-header | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| R1 phone-light-row-0 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 phone-light-row-1 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 phone-light-row-2 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 phone-light-row-3 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 phone-light-header | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| R1 ipad-light-row-0 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 ipad-light-row-1 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 ipad-light-row-2 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 ipad-light-row-3 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 ipad-light-header | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| R1 mac-weekly-card-0 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 mac-weekly-card-1 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 mac-states-card-0 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 mac-billing-card-0 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 mac-corrected-weekly-card-0 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 mac-corrected-weekly-card-1 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 phone-dark-row-0 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 phone-dark-row-1 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 phone-dark-row-2 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 phone-dark-row-3 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 phone-accessibility-xl-row-0 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 phone-accessibility-xl-row-1 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 mac-identity-component | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 mac-states-component | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 mac-billing-component | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R1 mac-refreshing-component | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | N/A |
| R3 mac-normal-final-card-0 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R3 mac-normal-final-card-1 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R3 mac-normal-final-row-0 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R3 mac-normal-final-row-1 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R3 mac-normal-final-row-2 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R3 mac-normal-final-row-3 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R3 mac-error-final | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | N/A |
| R3 mac-offline-final | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R3 phone-normal-final-row-0 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R3 phone-normal-final-row-1 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R3 phone-normal-final-row-2 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R3 phone-normal-final-row-3 | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |
| R3 phone-error-notice-final | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | N/A |
| R3 ipad-error-notice-final | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | N/A |
| R3 phone-offline-card-final | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | N/A |

## Evidence and cleanup

Forty baseline component pairs: `round-1/crops-complete/index.json`. Fifteen fresh final pairs: `round-3/crops-final/index.json`. These indexes include original/crop hashes and exact pixel boxes. Source capture dimensions/profiles are indexed in `capture-provenance.json`. Geometry uses rendered DOM, saved AX frames or explicitly documented original-image pixel measurements; sources were not stretched to hide differences.

| Phase | Observed milestone |
|---|---|
| Preparation/reference | Original reference read and six scenarios rendered before comparison |
| First native pass | Mac final-source launch 15:54:52 UTC, light correction launch 15:57:54 UTC |
| Component comparison | 40 measured baseline pairs inspected; F2/F3/F4 sent to parent |
| Recheck | Round-3 final Mac launch 16:16:47 UTC; actual offline shutdown/recovery captured |
| Report | 55 total pairs inspected and final verdict saved after final iOS35/36 review |

These are observed milestones, not inferred model-compute durations. axdriver's parent-window capture was recovered with the supplied isolated-popover capture. Raw AXScrollDown failed; the exposed CUA accessibility secondary action scrolled successfully without global HID input. A transient shared build-guard block and later screen lock were reported; parent resolved them before final capture. No unrelated app or production host was changed.

Audit app stopped. Audit-only light preference deleted. Reference server 8994 and its browser tab closed. Fixture 8987 was restored after the Mac check, then stopped by the parent. Parent stopped the other audit fixture/apps and restored the screen lock. Nothing was published.
