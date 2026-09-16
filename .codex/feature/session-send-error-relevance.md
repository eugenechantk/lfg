# Feature: Session send-error relevance

## User Story

As an LFG iOS user, I want “Message not sent” to appear only for a still-failed message in the session I am viewing, so opening an unrelated or already-reconciled session never shows a false failure.

## User Flow

1. Launch LFG or remain on the session list while background reconciliation runs.
2. Open a session that has no failed pending send.
3. See the session normally, without a stale “Message not sent” banner.
4. If a real send fails terminally, keep its failed row and show one short-lived banner in that same session.

## Success Criteria

- [x] SC1: A send-error event for another session is not presented in the current session. — **Verify by:** `TransientErrorPresentationTests` session-audience cases.
- [x] SC2: A send-error event is not presented after its failed pending row has reconciled or been removed. — **Verify by:** `TransientErrorPresentationTests` pending-send relevance cases.
- [x] SC3: Any error event older than its six-second lifetime is not presented when a session view appears. — **Verify by:** `TransientErrorPresentationTests` lifetime boundary cases.
- [x] SC4: A fresh terminal send failure with a matching failed pending row still presents in the affected session. — **Verify by:** `TransientErrorPresentationTests` positive case.
- [x] SC5: Navigating from the list into a live session with no pending send shows no send-error banner or pending strip. — **Verify by:** FlowDeck Simulator interaction recording and final screenshot.
- [x] SC6: The iOS app builds and the existing LFGCore suite remains green. — **Verify by:** `swift test` through FlowDeck-compatible package testing and `flowdeck build`.

## Platform & Stack

- **Platform:** iOS / iPadOS
- **Language:** Swift 6
- **Key frameworks:** SwiftUI Observation, LFGCore, Swift Testing/XCTest

## Test Strategy

Keep the relevance rule platform-neutral in LFGCore and cover the full decision table there. The app store supplies the event audience, age, current session, and currently failed pending-send IDs. Simulator validation proves the detail view consumes the rule at runtime.

## Tests

### Package unit

- `ios/LFGCore/Tests/LFGCoreTests/TransientErrorPresentationTests.swift`
  - hides a session-scoped event in another session — SC1
  - hides a pending-send event after its failed row disappears — SC2
  - hides an expired event at and after the lifetime boundary — SC3
  - presents a fresh event while its failed row still exists — SC4

## Implementation Details

- Enrich store error events with an audience and emission timestamp.
- Emit terminal send errors with the affected session and client ID.
- Have `SessionDetailView` ask the store for the relevant, still-fresh event instead of rendering the global slot directly.
- Make terminal failure replace any earlier queued-offline flags so the failed row exposes Retry consistently with its banner.
- Preserve global events for operations that do not yet carry session context.

## Decision Log

- **Validate relevance at presentation time.** Reconciliation can remove a pending row after the error event is emitted; tying visibility to the current failed-pending set prevents the banner from outliving the state it describes.
- **Retain a six-second TTL from emission, not from first view appearance.** The current presenter-owned timer lets errors wait indefinitely on the list and restart their lifetime in an unrelated detail view.
- **Make failure and queued-offline mutually exclusive.** The independent positive-path audit found both flags could remain true after a terminal rejection; because queued state renders first, it hid Retry and contradicted the banner.

## Verification Evidence

| SC | Command / action | Observed | Artifact |
| --- | --- | --- | --- |
| SC1–SC4 | `swift test --filter 'SendFailurePolicyTests\|TransientErrorPresentationTests'` | 12 tests passed, 0 failures | test output; both focused test files |
| SC6 | `swift test` | XCTest: 483 tests, 0 failures; Swift Testing: 144 tests in 21 suites passed | command output |
| SC6 | `flowdeck run -S 'cc-01a0951f'` | Final Debug binary built, installed, and launched on isolated iPhone 17 Pro / iOS 26.3 | FlowDeck build/runtime logs |
| SC4 | Disposable `Audit Stub` returned HTTP 400 for one synthetic message | Exact `sessionErrorBanner`; same pending row showed red failure icon and Retry | `.codex/evidence/20260912-182531-session-send-error-audit/fixed-positive-banner-tree.json`, `fixed-positive-retry.jpg` |
| SC5 | Independent FlowDeck list → live-session navigation | No `sessionErrorBanner`, “Message not sent”, or pending identifiers | `.codex/evidence/20260912-182531-session-send-error-audit/list-to-live-session-clean.mov`, `assertions.json` |

Independent audit verdict: **PASS**. See `.codex/evidence/20260912-182531-session-send-error-audit/evidence.md`.

## Residual Risks

The disposable fixture's terminal response spanned two bounded recordings because of Simulator transport latency. The exact terminal state is additionally captured in the retained accessibility tree and screenshot. No real session or message was mutated; the synthetic pending row and Audit Stub host were removed after verification.

## Bugs

- **Resolved:** A terminal HTTP rejection could leave `failed` and `queuedOffline` true together, making the pending strip say “Queued” instead of exposing Retry. The terminal transition now clears queued-offline state and is covered by `SendFailurePolicyTests`.
