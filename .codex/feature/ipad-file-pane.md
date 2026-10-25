# iPad file pane

Implements the approved [iPad split-preview design](https://claude.ai/artifact/F2B1MNbv5oxuscm237M9sD#page-5f9cfb675140). Canonical discussion and native mappings: `.claude/design/ipad-artifact-split/design.md` and `ipad-file-pane/components.md`.

## Flow and success criteria

Open a file, link, or Files pill from a session. The transcript and composer stay mounted while the reader changes selection, size, or presentation.

- [x] SC1: Landscape uses 720/420pt preferences, close/full-width drag endpoints, and a live composer. Three-column layout caps the wide reader at600pt.
- [x] SC2: Keep the sidebar only when400pt transcript +600pt pane +16pt handle fit. Close restores its previous state. The list button opens a320pt overlay with native search.
- [x] SC3: Reuse image, PDF, Markdown and video viewers; support native PiP through pane close, reopen, restore and Done. Render local HTML and links with WKWebView. Provide index, media tray, return chip, source reveal, Copy path and Open in Safari.
- [x] SC4: Portrait defaults to a native sheet. Optional top dock uses40/55/70%; keyboard uses40%. Windows narrower than600pt use the sheet.
- [x] SC5: Remember selection per session and width per kind. Arrivals mark the index without replacing the reader. Rewrites reload the open file in place.
- [x] SC6: Selected cards show Open. Show in transcript reveals the source, including outside the initial render window, below the header. Preserve the iPhone viewer flow. R9 regression and independent source review pass.

## Implementation

Pure layout, resource-index, arrival and revision policies live in LFGCore. SwiftUI owns presentation and per-session memory. WKWebView uses its persistent data store and authenticated host-file loading. Native AVPlayer retains its coordinator and loader while PiP floats.

The oldest source previously landed underneath the overlaid header. Explicit source jumps now add scroll clearance; returning to the newest messages removes it.

All twelve task files match the isolated worktree. `ipad-file-pane/source-manifest.json` records their hashes. `ipad-file-pane/implementation.patch` contains only this task's changes against the initial working tree. Changes are already integrated in the main checkout; XcodeGen has regenerated both projects.

## Verification

- LFGCore: **532 tests across79 suites pass**. Includes ten pane-policy/index tests and the HTML discovery regression. Log: `ipad-file-pane/swift-tests-r2.txt`.
- App tests: **8 pass**, covering PiP lifecycle/capability and native sizing. Their implementations are unchanged by the source-scroll fix.
- Recorded acceptance test: passes through draft editing, full width, file index, image replacement and close. Movie: `.codex/evidence/20261024-112805-ios-visual-audit/46-r7-acceptance-flow.mov`.
- Recorded historical-source regression: **passes in32.72s** against a402-message thread. Movie62 and `r9-source-passing.xcresult` are in the same evidence directory.
- Native PiP: movie57 covers playing, pane close/reopen, system restore and Done. Movie58 covers arrivals, rewrites, acknowledgement and independent reader memory.
- Final13-inch capture: `60-r8-ipad13-report-600.png/json` proves the600pt reader with sidebar and composer.
- Independent functional audit: `.codex/evidence/20261024-112805-ios-visual-audit/evidence.md`.
- Independent design comparison: `.codex/evidence/20261024-r7-ipad-design-verifier/evidence.md`.

## Review status

Functional verification and independent design comparison both pass. All six functional criteria pass. Final R9 captures cover portrait document40%, image55%, web70%, native sheet, Links, loaded local HTML, and the software keyboard reducing a70% dock to40%. Captures66,68–70,72–73 and75 are in the audit evidence directory. The independent design verifier inspected all seven final R9 states and returned PASS with no concrete visual mismatch under the accepted native mappings.

Movie63 records the final visual states and is valid (4509.06s,98.97MB); it includes long idle intervals between captures. Movie46 is the concise acceptance recording. Capture71 shows hardware-keyboard focus, not the software-keyboard state; use75 for that criterion. No commit, push, physical-device install or release.

The task uses a checksum-verified official FlowDeck1.33 binary through the existing build guard. The global installation and unrelated sessions remain untouched. An experimental PiP XCTest hit AVKit animation-idle waits and was removed; native FlowDeck recording57 supplies the passing runtime proof.
