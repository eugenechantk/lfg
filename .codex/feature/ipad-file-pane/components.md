# Native mapping

Canonical design: canvas `ipad-files`, Option A; exported `ia-a-*` and `ia-p-*` pages in `reference/`. The full discussion is session “iPad artifact side-by-side view”. The supplied artifact and local export identify the same canvas.

## Foundation

Use existing S2 adaptive colors and ReadableColumn. Pane: 26pt radius, 64pt header, 44pt circle controls, 8pt inner inset. Wide/narrow snaps: 720/420pt. Portrait: 40/55/70%. A sidebar remains only above 1016pt of remaining detail width.

## Components

| Component | Source | Apple HIG | Native target |
|---|---|---|---|
| Preview card and header | `ia-proto.dc.html` | Split views, Buttons, Toolbars | `FilePaneContainer`, `FilePaneReader` |
| Snap handle | `ia-proto.dc.html` | Gestures, Accessibility | Button with drag and spoken size |
| Files and links | `ia-a-files.dc.html` | Lists and tables, Segmented controls | Native Picker and ScrollView |
| Selected card | `ia-a-doc.dc.html` | Buttons, Feedback | Existing `MediaAttachmentsView` |
| Image and video strip | `ia-a-image.dc.html`, `ia-a-video.dc.html` | Image views, Playing video | Existing authenticated image and AVPlayer surfaces |
| Local HTML and web links | `ia-a-web.dc.html`, `ia-a-link.dc.html` | Web views | WKWebView and host-file URL scheme |
| Portrait sheet/dock | `ia-a-portrait.dc.html`, `ia-p-split-*` | Sheets, Split views | System sheet and top pane |
| Session overlay | `ia-a-list.dc.html` | Sidebars | Existing session list with scrim |

## State and behavior

The transcript remains mounted while opening, closing, and resizing. One selection replaces another. The index has separate Files/Links tabs. New arrivals update badges without selecting or scrolling. A rewrite changes the load token while keeping the same viewer. Selection and snap preferences persist per host/session.

Native menus contain Show in transcript, Copy path, and Open in Safari for web links. The approved design excludes Share, source view, tabs, and new windows. Esc closes the reader.

## Build order

Policy and index tests; layout shell; shared viewer; selection/index; web and relative assets; root sidebar coordination; Simulator interaction; independent visual/design review.
