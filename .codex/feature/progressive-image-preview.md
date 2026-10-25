# Progressive original image preview

## User story

Open a large canvas quickly, then inspect the original image at full detail.

## Flow

1. Open an image in the existing file viewer.
2. Display the small host rendition as soon as it arrives.
3. Download and prepare the original in the background.
4. Replace the rendition without resetting the current zoom or scroll position.
5. Keep the preview usable if the original fails. Cancel loading when leaving the file.

## Success criteria

- [x] SC1: Preview appears before a delayed original. Verify with app Swift tests and a recorded simulator fixture.
- [x] SC2: The original request has no rendition size; the displayed image has the original dimensions. Verify app tests and simulator accessibility state.
- [ ] SC3: Replacement preserves the visible region and allows inspecting source pixels beyond the old four-times zoom cap. Verify UIKit tests and recorded pinch/pan on iPhone and iPad.
- [x] SC4: A failed preview falls back to the original; a failed original retains the preview; cancellation never publishes a stale image. Verify app Swift tests.
- [x] SC5: Paging, non-image viewing, and original file sharing retain their behavior. Verify focused existing tests and simulator interactions.

## Decisions

Use the existing small rendition for speed. Fetch the unsized original immediately afterward through the authenticated client. Decode images away from the main actor. Keep one stable UIKit image view and its image coordinate system while replacing its pixels. No host restart or release is needed for this client change.

## Tests

App-target Swift tests cover progressive loading, errors, cancellation, replacement geometry, and zoom range. Existing core tests cover file sequence and original URL transport.

## Verification evidence

- Initial app-target Swift Testing run: eight loading and UIKit geometry tests passed. `app-tests.jsonl`.
- Focused core regressions: 14 tests passed for file sequences, original exports, and authenticated access. `core-tests.log`.
- Evidence directory: `.codex/evidence/progressive-image-preview/`.
- Final app-target run: all nine tests passed, including actual host URL construction. `app-tests-final.jsonl`.
- Self-verification: delayed preview then original on the real canvas, including zoom before replacement. Recording: `phone-progressive.mov`; screenshots: `phone-zoom-before-upgrade.jpg`, `phone-original.jpg`, `phone-full-detail.jpg`.
- The local fixture log shows `w=2400` followed by the unsized original request, with eight seconds of deliberate delay.
- Native iPhone XCUITest passed. It reads the actual `UIImageView` value as 727 x 2400 preview then 4784 x 15784 original, verifies identical image frame after replacement, and pinches beyond 4.1 times fit width. Combined app run: ten passed. `native-tests-final.jsonl`; recording: `native-pinch.mov`.
- Independent iPhone/iPad audit is finalizing the iPad native pinch check.

## Residual risks

Partial. The independent audit passes SC1, SC2, SC4 and SC5. SC3 remains blocked on native iPad deep-pinch verification after five attempts. See [blocker report](progressive-image-preview-blocker.md). No release or physical-device installation occurred.

## Native pinch verification

The FlowDeck synthetic pinch reported success without changing the image frame. A native XCUITest probe checks the actual pinch path and UIImageView accessibility value. The first probe could not find the scroll view because SwiftUI flattens that container in the accessibility tree. The revised probe pinches at the app center, inside the image viewport. It runs through the dedicated `LFGImagePreviewTests` scheme and the local fixture server, separate from the regular unit-test scheme.

## Reproduce native interaction test

Start the isolated fixture server from the repo root:

```sh
python3 .codex/evidence/progressive-image-preview/fixture_server.py
```

It uses the existing share-sheet canvas and cached 2400-pixel rendition. Port 8879 must be free. Run the dedicated `LFGImagePreviewTests` scheme through FlowDeck on a session simulator. The regular `LFG` scheme runs the independent unit tests without requiring this server.

```sh
flowdeck test -s LFGImagePreviewTests -S <session-simulator-UDID>
```

The independent iPad native probe failed its deep-zoom assertion after one large second pinch (image width 1408.21 points; required 3419.40). Full-resolution replacement and viewport checks passed. The next probe keeps the same strict threshold but uses repeated smaller native pinches, which keeps gesture endpoints within the viewport. Production code is unchanged while separating a gesture synthesis issue from a real zoom limit.

## Final status

Progressive loading is implemented. Overall completion remains blocked by iPad deep-pinch proof. Independent reports are `.codex/evidence/20261024-022958-progressive-final-audit/evidence.md` and `.codex/evidence/20261024-030434-progressive-final-reaudit/evidence.md`. Temporary instrumentation was removed, and the production view matches the originally verified source hash. The strict failing native iPad probe remains available in the dedicated test scheme; ordinary unit tests remain independent of the fixture server.

Final clean-source unit run: nine passed, zero failed (`final-clean-unit-tests.jsonl`). The local fixture server was stopped. No active simulator capture session remains.
