# Center the desktop destination switcher

Superseded by `single-row-desktop-switcher.md`: the user clarified that the switcher must remain on the original top bar at every width.

Keep Sessions and Tasks centered against the full window at narrow widths. The control must stay visible and clickable while resizing.

## Success criteria

- [x] Measure Sessions and Tasks at 180, 240, 320, 400, 500, 600, 760, 900, and 1200 points. The switcher stays visible and its center differs from the window center by no more than two points.
- [x] Check both sides of each responsive breakpoint and repeat while widening. No overlap with window controls or action buttons.
- [x] Switch views at narrow widths, open task details, and return. Selection and toolbar actions remain usable.
- [x] Run the desktop feature checks and an independent native visual audit.

## Decisions

At the narrowest widths, the switcher and macOS window controls cannot share one row. Use a centered toolbar row when needed rather than hiding the switcher in overflow. Keep the 180-point minimum width.

Preserve concurrent changes. Install the verified update on Pro and Air under the user's existing installation request.

## Verification Evidence

The baseline measured offsets of 17 points at 900, 87 at 760, and 85 at 500. The switcher disappeared at 400 and below. Evidence: `.codex/evidence/centered-desktop-switcher/baseline-sessions/measurements.json`.

The final layout places the switcher in a full-width toolbar row below 1000 points. Wider windows retain the single-row native toolbar.

The final candidate passed 18 widths in Sessions and Tasks, including 999/1000/1001 and 1199/1200/1201 points. Maximum center error was 0.5 points. Task details passed 180, 400, 999, 1000, and 1001 points. All measurements use the union of the rendered segment bounds. The signed desktop build passes all 180 feature checks.

The independent native audit passed 12 widths per destination. It confirmed zero collisions at the layout boundary and working navigation at 180 points. The window stayed 180 by 640 points through task detail and return. Report: `.codex/evidence/centered-desktop-switcher/auditor/evidence.md`.

Apple documents native toolbar centering as conditional on available space. The compact row avoids that condition while keeping the native segmented control: https://developer.apple.com/documentation/appkit/nstoolbar/centereditemidentifiers

## Installation

Installed and launched the same signed build on Pro and Air. Each installed app passed all 180 desktop checks. Signature, executable checksum, and running process path were verified on both hosts. Previous app bundles remain in timestamped backups. Evidence: `.codex/evidence/centered-desktop-switcher/deployment/pro-verification.json` and `air-verification.json`.

The independent visual audit ran on Pro. Air verification covers installation and execution; its visible interface was not inspected remotely. No commit or push was made.
