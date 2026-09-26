# TestFlight crash 202609261231

## User Story

As a TestFlight user, I can use LFG build `1.3.0 (202609261231)` without the app terminating on the reported path.

## User Flow

Launch with live data, open a session from the list, open More, traverse the Switch model submenu, dismiss it, and repeat.

## Success Criteria

- [x] SC1: Retrieve and symbolicate the submitted TestFlight crash for build `202609261231` when App Store Connect finishes ingesting it, or establish the current signature from a local runtime sample.
- [x] SC2: Remove the only new explicit runtime-trap paths in this build: actor assertions in native menu callbacks that UIKit may deliver asynchronously.
- [x] SC3: Add a regression test that fails for the reported condition before the fix and passes afterward.
- [x] SC4: Reproduce the relevant runtime path in Simulator without a crash after the fix.
- [x] SC5: Independently verify the fixed runtime behavior when the affected path is UI-impacting.

## Test Strategy

- Use the App Store Connect beta feedback crash submission as production ground truth.
- Add the narrowest deterministic source-invariant regression at the owning layer.
- Run the focused suite first, then the broader relevant suite.
- Use FlowDeck to build and exercise the reported runtime path in Simulator.

## Tests

- `src/ios-session-menu-threading.test.ts`
  - Guards both UIKit menu callback bridges against `MainActor.assumeIsolated`, requires explicit main-actor hops, and prevents the navigation proxy from restoring recursive hierarchy searches.
  - Passed with 2 tests and 9 assertions on 2026-09-26.
- Focused Simulator regression: open the native More menu, traverse a submenu, dismiss it, and repeat without termination.
  - Passed twice on isolated simulator `71442893-3249-4AE6-AE32-7E64D09AB374`; final AX check for the model submenu scored 0.97, and the post-reopen process used 1% CPU.
- Broader verification: `LFGCoreTests` plus a FlowDeck build.
  - FlowDeck build passed; `LFGCoreTests` passed 796 tests with 1 expected live-terminal skip.
- Independent visual audit:
  - PASS on isolated simulator `6CD7AE16-9BB1-47AE-B3FC-BAC39755B6F4`; a real session opened and More → Switch model completed three times while the app remained responsive under the same PID.
  - Evidence: `.codex/evidence/20260926-131220-ios-visual-audit/evidence.md` and `repeated-menu-flow.mov`.

## Implementation Details

- Simulator reproduction showed the app becoming unresponsive immediately after a session opened. A five-second process sample recorded 99% CPU with all 3,008 main-thread samples recursively repeating `sessionOptionsSource(in:)` from `InstallerView.layoutSubviews()`.
- Replace the recursive functional view-hierarchy searches with explicit iterative traversal, eliminating the unbounded main-thread recursion.
- Build `202609261231` also adds two `MainActor.assumeIsolated` calls inside UIKit menu callbacks. Replace both assertions with `Task { @MainActor in ... }` so callbacks safely hop to the actor instead of trapping when delivered off-main.
- The App Store Connect API currently exposes only an older July crash submission; that report is a previously fixed BGTask queue-isolation crash and is not being misattributed to this incident.

## Residual Risks

- Simulator reproduction may not perfectly match the tester's hardware and production optimization.

## Bugs

- TestFlight build `202609261231` terminated on a user-reported path. App Store Connect ingestion is pending; the matching local path reproduced as a 99% CPU main-thread hang in the newly shipped navigation-bar proxy.
