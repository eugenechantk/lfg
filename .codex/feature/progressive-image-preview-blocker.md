# Blocker: iPad deep pinch verification

## Delivered behavior

The native file viewer loads its small rendition, then downloads and displays the unsized original. Nine app unit tests and fourteen core regressions passed. Native UI probes read the actual image as 727 x 2400 pixels first, then 4784 x 15784 pixels. iPhone native testing proved identical viewport geometry and pinch zoom beyond 4.1 times fit width. Independent evidence also proves loading and viewport retention on iPad, failure fallback, PDF paging, and original sharing.

## Open criterion

SC3 requires deep native pinch proof on both platforms. iPad UI probes failed that threshold. This task remains partial; no release was performed.

## Attempts

1. One large native second pinch: final image width 1408.21 points, below 3419.40 required.
2. Repeated smaller native pinches: 995.48 points, below the same threshold.
3. Pinches targeted to the visible image viewport using a DEBUG accessibility element: 970.19 points.
4. Native recognizer tracing with shared-container output: same failed threshold; no trace file produced.
5. Tracing to the app's temporary directory: same failed threshold. The displayed original reports 4784 pixels wide. The scroll view permits maximum zoom 6.58047 with fit scale 1.14718, which permits 5.74 times fit width. The observed current zoom remained 1.33451.

The trace is `.codex/evidence/progressive-image-preview/ipad-native-zoom-state.json`. The final two attempts were diagnostics, not speculative changes to shipping gesture behavior. Temporary diagnostic and accessibility hooks were removed afterward. The production view was restored byte-for-byte to its previously verified source hash.

## Current hypothesis

The native synthetic gesture does not reach the expected zoom on iPad despite a sufficient configured maximum. The evidence does not yet distinguish gesture synthesis from a runtime interaction issue. Direct physical-iPad verification or inspection of actual touch delivery is needed next. Do not infer that a high configured maximum proves the physical gesture works.

## Independent audit

- `.codex/evidence/20261024-022958-progressive-final-audit/evidence.md`: FAIL on iPad SC3; other four criteria pass.
- `.codex/evidence/20261024-030434-progressive-final-reaudit/evidence.md`: FAIL after smaller pinches; strict criterion retained.

The iOS workflow requires a blocker report after five failed attempts. Further guessing stops here. No commit, push, physical-device installation, or TestFlight release occurred.
