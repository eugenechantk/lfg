# iPad file pane — built app screenshots

Copied 2026-11-03 from the Pro: `~/dev/personal/lfg/.codex/evidence/20261024-112805-ios-visual-audit/`
(gitignored, Pro only; 218 files over audit rounds R1–R9). One file per state, the newest round that shows it.
Fixture sessions on the iPad simulator. Build: ad0ed61, shipped in TestFlight 202610252146 (v1.4.1, Oct 25).

| State | File | Round | Mode |
|---|---|---|---|
| Doc, wide 720 | 45-r7-preflight-open-report.png | R7 | light |
| Doc, narrow 420 | 19-r2-report-narrow-dark.jpg | R2 | dark |
| Full width + chip | 24-r2-report-full-width-dark.jpg | R2 | dark |
| Image + media strip | 38-r4-image-media-tray-light.png | R4 | light |
| Video, native controls | 08b-video-controls-visible-dark.jpg | R1 | dark |
| Video, Picture in Picture | 48-r7-pip-floating.png | R7 | light |
| Web link + address | 39-r4-web-address-light.png | R4 | light |
| Local HTML (portrait sheet) | 73-r9-local-html.png | R9 | light |
| Files & links index | 67-index-current.png | R9 | light |
| Links tab | 69-r9-links-selected.png | R9 | light |
| ••• menu, file | 37-r4-report-actions-menu-light.png | R4 | light |
| ••• menu, link (Open in Safari) | 40-r4-web-actions-menu-light.png | R4 | light |
| List overlay | 54-r7-session-overlay.png | R7 | light |
| Close restores the list | 12-close-restores-sidebar-dark.jpg | R1 | dark |
| New file: dot, pane stays | 58b-new-file-keeps-reader.png | R8 | light |
| Open file updated in place | 58c-open-report-rewritten.png | R8 | light |
| Show in transcript | 62f-r9-source-revealed-77.png | R9 | light |
| 13-inch, list stays, 600 pane | 60-r8-ipad13-report-600.png | R8 | light |
| Portrait sheet | 72-r9-native-sheet.png | R9 | light |
| Portrait split, doc 40% | 66-r9-portrait-doc40.png | R9 | light |
| Portrait split, image 55% | 68-r9-portrait-image55.png | R9 | light |
| Portrait split, web 70% | 70-r9-portrait-web70.png | R9 | light |
| Portrait split, keyboard drops to 40% | 71-r9-keyboard40.png | R9 | light |

Gaps: from R4 on, almost every shot is light mode; most dark shots are from R1–R3, before later fixes. No real-device shots. Gallery: index.html (rebuild with `uv run --with pillow python build.py`).
