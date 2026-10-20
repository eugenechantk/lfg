# Session ending feedback and swipe actions

Product tier: maintained iOS app.

## User story

End a session from its options or a leftward swipe. Show the request immediately while the host finishes closing it.

## Success criteria

1. The session title bar shows “Ending session…” in red throughout the close request.
2. A trailing swipe offers red End and the existing Hide directory action. Full swipe runs End.
3. A closing row stays visible, dims, shows the ending state, and rejects duplicate actions.
4. Successful closure removes the row from the current list. Transcript history remains stored.
5. A failed close restores the row and controls and shows the existing error. Retry remains possible.
6. Ending from the options sheet needs no confirmation and dismisses the detail only after success.
7. Closed, externally owned, and not-yet-created sessions offer no End action.

## Design

Use native swipe actions. Put End first so it owns the full swipe. Give End a red tint without the destructive button role: that role removes a List row before the async close finishes.

Keep the original session snapshot during closing. A live update may remove or archive the row before the HTTP response arrives. The local closing state must win until that response settles.

Keep successful closes out of this run's list, including stale snapshots and search results. Keep history in the store. Clear this suppression if the session resumes.

## Verification

- Swift Testing: close lifecycle, duplicate requests, failure and retry, snapshots during close, stale snapshots after success, eligibility, red status copy.
- Build the iOS app with FlowDeck.
- Record the simulator using delayed synthetic hosts. Exercise partial swipe, End, full swipe, Hide, options End, failure and retry.
- Independent visual evidence audit after implementation.

## Results

- Focused suites: 32 Swift Testing tests and four XCTest cases passed. Log: `session-ending-tests.txt`.
- iOS simulator build passed. Log: `session-ending-build.jsonl`.
- Full LFGCore sweep: 648 XCTest cases completed without failures, with one skipped. Swift Testing passed 485 of 486 tests. The unrelated, untracked `ScheduledTaskAutomaticRetryTests.swift` fails `shiftedScheduleProgressUsesItsEffectiveAnchor` at line 58. No scheduling files were changed for this feature.
- Delayed synthetic hosts run on ports 18941 and 18942. Their close request takes six seconds. The failure row rejects its first attempt and accepts its second.
- Simulator: `cc-5462a9ff`, `7C6F0525-4F97-49CA-806B-48453F8ABA1C`. Launch uses the existing isolated fixture defaults and local synthetic hosts.
- Independent visual audit: PASS on iPhone 17 Pro, iOS 26.3. Report: `.codex/evidence/20261020-120500-ios-visual-audit/evidence.md`.
- Recordings prove partial swipe, full swipe, options End without confirmation, the six-second pending state, success removal, failure and retry, Hide without closing, and no End for external or local-pending sessions.
- Request counts prove one close per action. The failure row has two attempts: one failure and one explicit successful retry.

## Implementation

`SessionCloseTracking` holds pending snapshots and the IDs ended during this app run. `SessionStore` keeps pending routes and list groups stable. A successful response removes the row immediately; the fleet refresh runs afterward. Local resumption clears the list suppression.

The options sheet sends End after dismissal. It no longer asks for confirmation. The detail status gives Ending priority over activity, offline, question, and working states.

The native End swipe button has a red tint without a destructive role. This keeps SwiftUI from removing the row before the response. It comes before Hide so full swipe selects End. The previous optional third pattern action was removed to keep exactly two actions.

Swipe failures use the existing transient error banner in the session list. The row becomes usable again for retry.

## Residual risks

The simulator audit proves gesture ordering, row retention, dimming, status styling, and navigation with synthetic delayed hosts. This feature did not change or exercise the real host's process-termination code. No release or physical-device install was requested or performed.
