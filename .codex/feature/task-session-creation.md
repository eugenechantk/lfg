# Task setup uses New Session

## Flow

On Tasks, tap +. The existing New Session composer opens with the title New task.
Choose the host, directory, and model as usual. Describe the task and timing.
Send opens the normal session view immediately. Back returns to Tasks. The
same session also appears in Sessions, where Back returns to the session list.
The agent helps clarify and save an LFG schedule through the host's task API. No separate task chat remains after
startup. Desktop setup conversations open their normal iTerm session.

## Success criteria

- [x] iPhone and iPad reuse the existing composer and all three pickers.
- [x] Send opens one normal session view, with the user's first message once.
- [x] Task setup uses the selected host, model, directory, owner, and timezone.
- [x] The saved run directory can differ from the setup session directory.
- [x] The agent receives schedule setup instructions, without running the work.
- [x] Unsupported hosts fail and never fall back to executing the request.
- [x] Follow-up messages use the normal session composer.
- [x] Back returns to the originating Tasks or Sessions list.
- [x] The saved task appears when returning to Tasks.
- [x] Ordinary New Session creation remains unchanged.
- [x] Edit chat and desktop creation also hand off to the normal session surface.

## Implementation

An optional request purpose changes only the initial endpoint. Existing optimistic
creation, uploads, error handling, retry, ID remapping, and navigation remain shared.
The presentation waits for dismissal before selecting the new session. The transcript
retains the raw setup prompt but renders only the user's request in its user bubble.

## Verification

Swift client tests cover routing, request data, older hosts, decoding, transcript
display, and optimistic reconciliation. Backend tests verify selected options and
that startup creates no saved task or execution. Native recordings cover creation,
follow-up, return navigation, and the earlier list and editing changes. Isolated
fixtures simulate agent replies while using real task persistence and API routes.
No live provider execution is claimed by those fixtures.

## Release

Source changes and local verification only. No deployment, commit, or TestFlight.

Verified in `.codex/evidence/task-session-creation/verification.md`.
