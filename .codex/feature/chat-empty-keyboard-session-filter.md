# Chat focus, empty state and session visibility

Product tier. Chats retain their own session lifecycle without appearing in Sessions.

## Success criteria

- The empty chat icon, title and caption form a centered group in the transcript viewport, above the composer, on iPhone and iPad.
- Tapping the transcript dismisses the keyboard without deleting the draft. Scrolling, message selection, links and sending still work.
- Sessions excludes durable chat sessions, their explicitly owned children and provider directories from local and searched rows. Its running and attention counts follow that population.
- Chats, chat badges, deep links and notification routing retain access to the underlying sessions. Ordinary coding sessions remain visible, including those with chat in their title or project directory.
- Desktop Sessions uses the same membership policy.

## Diagnosis

The empty placeholder shares the populated transcript's bottom anchor and content-sized stack. No tap gesture clears composer focus. Sessions currently renders the API's durable virtual sessions; provider processes are already suppressed server-side.

## Verification

Add Swift Testing coverage for explicit ownership, older chat IDs, provider directories and ordinary-session negative cases. Run the package suite and native builds. The independent iOS visual evidence auditor must record empty-state placement, keyboard dismissal with draft retention, Sessions search filtering and continued Chats access on owned iPhone/iPad simulators. Use isolated fixture data only.

## Scope

Keep the general session store intact. Filter the presentation projection and search union. Preserve existing shared-chrome changes and unrelated work. No commit, push or release requested.

## Implementation and current checks

A shared SessionListMembership policy serves iOS and desktop. iOS adds a Sessions-only projection without changing the general filtered session population. Local rows, searched rows, running count, hidden-directory count and the Sessions attention badge use that policy. Chat badges and routing keep the original population.

The empty transcript has its own full-area branch. Populated transcripts retain their bottom anchor and paging behavior. A simultaneous content tap clears composer focus; the composer remains outside that gesture via the existing safe-area inset.

- Red check: the new membership tests failed before the policy existed.
- Green: 588 Swift tests across 91 suites pass, including four new ownership tests.
- iPhone native build and launch pass at 03:50:49 UTC on 2026-11-04.
- Final Mac native build passed at 03:51:45 UTC. Headless desktop feature tests passed 287 assertions, including the actual Sessions visibility projection.
- Independent native audit PASS: iPhone plus iPad portrait and landscape. Blank transcript and populated-message taps dismiss the keyboard while retaining exact drafts. Refocus/send and local/search filtering pass. Evidence: `.codex/evidence/chat-focus-session-filter-audit/evidence.md`.

## Residual risks

Native interaction evidence uses isolated local hosts and owned simulators. Physical-device delivery, production hosts and release distribution are outside this change. Desktop verification covers compilation and its real list projection through headless feature tests; no desktop GUI behavior is claimed.

## Native result

The placeholder group sits 13 points above the transcript midpoint on iPad portrait and 12 points above on landscape, consistent with the native ContentUnavailableView optical placement. It fills the transcript area rather than sitting at its bottom. The auditor observed one simulator shutdown during a recording/orientation transition, rebooted through FlowDeck and reproduced the final landscape flow successfully. No product failure was observed.

## Final state

The canonical iOS project is regenerated. The temporary review spec and scheme remain beside the earlier chrome evidence. Both owned native capture sessions are stopped, hardware keyboards are restored and iPad is back in portrait. The isolated fixture is stopped. Saved FlowDeck configuration and audited source hashes remain unchanged. No commit, push, host restart or release was performed.

The fixture did not contain link-rich or long transcripts. Those interactions were outside the visual proof; the simultaneous tap gesture preserves native gesture arbitration, and populated-message tap/send flows passed.
