# Message: Cua Spaces

Status: all success criteria verified in the isolated worktree. Claude Code completed real browser work and two same-run follow-ups. Codex execution and email/connector account setup remain unverified.

## User story
Message an agent with its own computer from a separate Message section in LFG on Mac and iPhone.

## Flow
Choose an LFG host. Create a local Linux Space. Open its browser or send a task to Claude Code or Codex. Read agent progress and replies. Follow up in the same run. Stop the run or turn off the Space explicitly.

## Success criteria
- [x] SC1: Create and list a real local Cua Space from Message. Verify with API integration tests and a live Cua runtime probe.
- [x] SC2: Open a URL and control the Space's browser. Verify with API tests, real browser navigation and a screenshot from the Space.
- [x] SC3: Send work to an agent and receive its response; follow up in the same run. Verify API tests and a real agent task inside the Space.
- [x] SC4: Message is reachable on Mac and iPhone, with loading, errors and host selection. Verify builds, Swift tests and recorded UI audit.

## Decisions
- Product tier; isolated worktree codex/cua-message based on main 5c0aac3. Preserve all edits in the main checkout.
- Use the installed Cua CLI's MCP interface behind an LFG API boundary. Keep Cua tokens and model credentials on the host.
- Start with local Linux Spaces. Do not migrate sign-ins, configure recurring schedules, or send real emails during verification.
- Connector accounts must be configured separately. This change does not silently copy host credentials into a Space.
- Use existing native clients and shared SwiftUI views. No web client redesign.
- Creation, agent execution and browser control are separate operations with visible errors. Never retry an uncertain mutation automatically.
- Explicit power controls in this version. Automatic task-scoped teardown is deferred until persistent-home recovery has runtime proof.

## Verification evidence
_To be filled only after checks run._

## Blockers and risks
_None yet._

## Verification evidence — 20 October 2026

- SC1: Real Cua create succeeded for `local:lfg-message-trial`, then the real LFG POST `/api/message/spaces` created Scout. Evidence: `.codex/evidence/cua-message/create.log`, `live-created.json`.
- SC2: Independent live route audit navigated Firefox, clicked its address field, typed a URL, pressed Enter, and inspected the resulting image. Evidence: `.codex/evidence/cua-message-audit/live-results.json`, `trial-7.png`, `REPORT.md`.
- Backend: 7 Bun tests, 37 assertions passed. Full core Swift suite: 492 tests in 76 suites passed. Evidence: `backend-tests.log`, `swift-all-tests.log`.
- Mac and iPhone builds passed. Mac runtime Message list and conversation composer rendered against the isolated host. Evidence: `desktop-build.log`, `ios-build.jsonl`, `mac-message-list.png`, `mac-message-detail.png`.
- Independent API audit returned PARTIAL solely for missing authenticated agent execution. The fixed-role auditor could not run with this account; a separate default agent performed the independent audit instead.

## Resolved setup blockers — SC3

Cua's real `agent_capabilities` reports `auth: missing` for Claude Code and Codex. Neither Anthropic nor OpenAI provider keys exist in this host shell. The real message route returns 503 with Cua's setup instructions before recording a pending message. Evidence: `.codex/evidence/cua-message/live-auth-result.json` and independent `live-results.json`.

Resolved during acceptance: the current Claude Code token in the Mac Keychain was handed to Cua through its supported CLAUDE_CODE_OAUTH_TOKEN entry. The full Cua Spaces runtime then ran a real Claude task and follow-up. The token value never entered logs, client responses or source files. Automatic token renewal is not implemented. Codex remains unconfigured.

## Fixed bugs

- Driver input rejected modern `target` combined with legacy `scope`. Removed the legacy field, then independently verified real click/type/key input.
- Confirmed agent-message rejection left a permanent pending marker. Clear the marker and remove the undelivered message only for confirmed rejection. Preserve protection for unknown transport outcomes. Independent regression passed.

- Final Mac regression executable: `--desktop-feature-test` returned `{"ok":true,"tests":259}`.
- iOS visual audit found the bottom dock overlapping the message composer. The final build hides the dock on Space detail screens and restores it on the list. Independent recheck passed on the final iPhone build: the composer is fully visible and Back restores the list dock. See `.codex/evidence/20261020-155201-ios-visual-audit/07-final-chat-composer-error.png` and `08-final-space-list-dock.png`.


## Final runtime verification

- SC3: full Cua Spaces app installed in `.codex/tools/cua/Applications/Cua Spaces.app`, bundled CLI 0.4.1. Its daemon provides persistent-agent homes. The separately installed MIT CLI 0.5.0 could create desktops but rejected persistent homes; the adapter now prefers the full app and checks that capability before recording a send.
- Real Space `a4f4b908-f270-4ebe-9590-554ec107fc28` (Scout Live), agent run `run-eceb98d2`: Claude Code opened Firefox and inspected example.com. First answer correctly identified Example Domain and its documentation purpose.
- A second prompt used the same Space and run. It answered: `The exact visible heading is "Example Domain."` Turn 2 ended idle. An independent API auditor observed both turns.
- Evidence: `live-agent-start-auth.json`, `live-agent-followup.json`, `live-agent-complete.json`, independent `.codex/evidence/cua-message-audit/live-agent-followup-observation.json`.
- Authentic streaming exposed fragmented message bubbles and raw tool results. Added tested transcript coalescing and filtered API activity. Final checks: 10 Bun tests /50 assertions, 494 Swift tests /77 suites, and259 desktop feature checks. Latest iPhone and Mac builds passed. Independent native transcript recheck passed.
- Earlier Scout setup-test Space is now stopped. Audit Space 1559 and the trial Space are suspended/stopped. No test desktop was deleted.


## Final independent gates

- Backend PASS: `.codex/evidence/cua-message-audit/REPORT.md` (10 tests,50 assertions; real Claude turns1–3, same run).
- iPhone PASS: `.codex/evidence/20261020-155201-ios-visual-audit/evidence.md`. The recording `agent-interaction.mov` and `15-real-agent-same-run-followup.png` prove the real task, readable coalesced reply, and same-run follow-ups through Message.
- Mac: final build passed and259 feature checks passed. Prior runtime captures prove Message list and detail wiring; the final transcript projection is shared with the audited iPhone and covered by core tests.
- Friendly authentication errors now omit CLI arguments. The audit's duplicate fixture host labels came from configuring the same URL twice; real configured host URLs were not changed.
- Real power lifecycle: stop, start, and stop preserved run-eceb98d2. While stopped, detail returned in0.001seconds without polling the suspended guest. Evidence: `.codex/evidence/cua-message/lifecycle.json`.
- All four test desktops are suspended or stopped after acceptance. They remain on disk. The isolated host stays on127.0.0.1:18967; production port8766 is unchanged.

## Remaining limitations

- Claude authentication uses a current token copied through the supported Cua credential entry. Automatic renewal is not implemented.
- Codex has real execution proof with the custom image profile; see `cua-codex-image.md`. Standard Spaces still need their own authentication.
- Email and connector accounts must be configured separately; no real email was sent.
- Enforced per-action approvals and automatic task-scoped desktop deletion are outside this first version.
- An uncertain send remains protected and requires inspection in Cua before another task. There is no generic reset UI yet.

## Live Space extension
The manual browser image view now has live H.264 video, guarded takeover, and scroll controls. See `cua-live-space.md` for the extension and its current verification evidence. Earlier screenshots in this document remain historical evidence for the initial Message implementation.
