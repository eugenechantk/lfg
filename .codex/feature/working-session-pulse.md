# Working session indicators

## User story

Working session rows show their status and elapsed time without extra dots. The green dot at the left pulses to show ongoing work.

## Success criteria

- [x] SC1: Working rows read `Working 3m` (or the current duration), with no inline dot or separator. Verify with the existing row presentation test and a simulator screenshot.
- [x] SC2: Only the green side dot on a working row pulses. Verify with a simulator recording beside unread, idle, and closed rows.
- [x] SC3: Reduce Motion shows a steady green side dot. Verify with a simulator recording after enabling the actual system setting.
- [x] SC4: Text, row geometry, elapsed-time updates, and other status indicators remain intact. Verify with row/clock tests and simulator comparison.

## Decisions

- Scope is the iOS session list. The session detail header keeps its existing formatting.
- Keep the solid 8-point green core. Animate a soft halo within the existing side gutter.
- Isolate animation to the dot so the row and its clock do not redraw on every animation frame.
- Stop the pulse when Reduce Motion is on or the scene is inactive.
- Use the existing network-free session time fixture. Add a minutes-old working row for runtime verification. Verify Reduce Motion through Settings.

## Verification evidence

- The focused Swift package run passed: 15 tests across row, clock, and time suites. Output: `.codex/evidence/working-session-pulse-tests.log`.
- FlowDeck built and launched the Debug fixture on this session's isolated iPhone 17 Pro / iOS 26.3 simulator, D3D846B6-1997-4938-B4D3-56EA6E13D584. Output: `.codex/evidence/working-session-pulse-run.jsonl`.
- Self-check screenshot shows `Working 1m` and `Working 3m`, with no inline dots. Unread, idle, and closed retain their normal labels and side dots.
- Self-check recording: `.codex/evidence/working-session-pulse.mov`. Motion measurements: `.codex/evidence/working-session-pulse-motion.json`.
- The full Swift package suite passed: 648 XCTest cases executed, one unrelated live-terminal test skipped, and 457 Swift Testing cases passed. Output: `.codex/evidence/working-session-pulse-full-tests.log`.
- Independent iOS visual audit: PASS on SC1–SC4. Report: `.codex/evidence/20261017-142226-ios-visual-audit/evidence.md`. Actual Reduce Motion reduced working-dot luminance variation from about 3.0 to 0.074/0.017. The elapsed clock advanced from 53s to 1m. Other dots stayed static. The auditor restored Reduce Motion to off and stopped the capture session.

## Residual risks

Verified in the isolated iPhone 17 Pro / iOS 26.3 simulator. Physical-phone appearance remains unverified. No server changes are involved.

## Resolved verification issues

- The initial fixture attempted to override the read-only Reduce Motion environment value. Removed that override and switched verification to the actual Settings control. The final FlowDeck build passed.
