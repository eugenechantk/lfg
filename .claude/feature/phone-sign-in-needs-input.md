# Feature: phone-sign-in-needs-input

## User Story

As Eugene, when an agent asks me to sign in to a website from my iPhone, I want the session to show as "needs input" and my phone to get the same push notification an AskUserQuestion produces, so that a sign-in request never sits unnoticed while the agent waits (up to 16 minutes) on it.

## User Flow

1. An agent hits a login wall and runs `lfg browser-sign-in request --session <sid> --target <browser> --url <login-url>` (the `request-phone-sign-in` skill). The request is stored `waiting` in `PhoneSignInRequests`.
2. Within one pump tick the session's `prompt` becomes a synthesized sign-in prompt ("Sign in to <website> on your iPhone"). The session list groups it under Needs input; the Live Activity shows a needs-input row.
3. The push watcher sees the prompt appear and sends a `needs-input` APNs push whose body is that question — even though the agent's turn is still in flight (it is blocked in the waiting command).
4. Tapping the push opens the session. The prompt panel shows the sign-in request with a "Sign in to <website>" button that opens the existing phone sign-in sheet for that request.
5. Eugene signs in and taps Done (or Cancel), or the request expires / the browser goes offline. The request leaves `waiting`, the prompt retracts on the next tick, and the session returns to Working/Idle.

## Success Criteria

- [x] SC1: A `waiting` sign-in request for a session yields a prompt from `resolveSessionPrompt` when no real AskUserQuestion / pane prompt is present; a real prompt wins over it — **Verify by:** unit test in `src/phone-sign-in-requests.test.ts` (`phoneSignInPrompt`) + serve-level resolution test.
- [x] SC2: The synthesized prompt reaches the REST snapshot (`GET /api/sessions` → `prompt`) and the journal `prompt` delta, so `sessionDisplayState` = `needsInput` — **Verify by:** live probe on the deployed host: create a request via the local API, `curl /api/sessions` shows `prompt.source == "phone-sign-in"`, journal row appears.
- [x] SC3: The push watcher emits a `needs-input` push when a prompt appears while the session is busy (the sign-in case, and also AskUserQuestion which today is masked by the busy gate) — **Verify by:** `reduceTransition` unit tests + `runPushTick` test with `obs(true, true, "Sign in …")` after a busy seed; live: a push arrives on the phone / `liveactivity.log` shows a needsInput row.
- [x] SC4: The prompt retracts when the request leaves `waiting` (cancel / complete / expiry / offline) — **Verify by:** unit test (helper returns null for non-waiting) + live probe: cancel the request, `/api/sessions` prompt goes null.
- [x] SC5: iOS renders a sign-in prompt as a sign-in panel (no numbered options, no Escape-sending Dismiss) with a button that opens the sign-in sheet for that request — **Verify by:** `AgentPrompt` decode test in LFGCore (`signIn` field) + simulator screenshot of the panel against a host serving the prompt.
- [x] SC6: No regression in existing needs-input / finished push behaviour — **Verify by:** `bun test src/push src/journal-pump.test.ts src/session-state*.test.ts src/phone-sign-in-requests.test.ts src/browser-sign-in*.test.ts` green; `swift test` for LFGCore green.

## Platform & Stack

- **Platform:** Backend (Bun server) + iOS client
- **Language:** TypeScript, Swift
- **Key frameworks:** Bun, SwiftUI, LFGCore (Swift Package)

## Steps to Verify

1. `bun test <files>` for server tests.
2. `cd ios/LFGCore && swift test` for the client model tests.
3. Deploy: restart the server by port (`lsof -nP -iTCP:8766 -sTCP:LISTEN -t`), confirm the new process answers.
4. `POST /api/browser-sign-in/requests` with the local agent token for a live session → `GET /api/sessions` shows the prompt; `~/.lfg/liveactivity.log` shows `needsInput`; phone gets a push.
5. `POST /api/browser-sign-in/requests/<id>/cancel` → prompt clears.
6. Build the iOS app with FlowDeck, point it at a host serving the prompt, screenshot the panel.

## Implementation Phases

### Phase 1: Server — synthesize the prompt and push it

- Scope: `phoneSignInPrompt` helper; `resolveSessionPrompt` fallback; pump passes `sid`; watcher observes sign-in prompts; reducer announces a prompt when it appears regardless of busy.
- Success criteria covered: SC1–SC4, SC6 (server half)
- Verification gate: server tests green + live probe.

### Phase 2: iOS — render the sign-in prompt panel

- Scope: `AgentPrompt.signIn`; `PromptPanelView` sign-in variant; detail view routes the button to the sign-in sheet; hide the duplicate composer row while the panel shows the same request.
- Success criteria covered: SC5, SC6 (client half)
- Verification gate: LFGCore tests green + simulator screenshot.

## Decision Log

- **Ride the existing `prompt` primitive instead of adding a parallel `signInPending` field.** `prompt` already flows through the journal delta, the REST snapshot (`journal.latestPrompt`), the watcher, the Live Activity row, and the client's display ladder (prompt → needsInput). A new field would need all five re-plumbed plus the parity tests. Alternative rejected: separate state.
- **A real prompt outranks the sign-in prompt.** If the waiting `browser-sign-in request` Bash call itself needs a permission answer, that dialog must be answered first, so `resolveSessionPrompt` checks transcript and pane prompts before the sign-in fallback.
- **The reducer now announces a prompt the moment it appears, even while busy.** Journal evidence (10 most recent AskUserQuestion prompts) shows every one was answered before `busy` ever went false — the busy gate meant no needs-input push fired for any of them; the only way one could fire was the 15-minute STALL demotion. The sign-in case is structurally the same (the agent is mid-Bash-call). Rather than special-casing sign-in, a prompt appearing is treated as the needs-input moment, and busy→idle with a prompt that was already announced no longer re-fires. Risk: a pane-scraped false-positive prompt while busy can now push (deduped at 10s); the app already showed those as needs-input, so this surfaces an existing misread rather than creating one.
- **iOS: no Dismiss on a sign-in panel.** Dismiss sends Escape to the pane, which would interrupt the agent's waiting command. Cancelling lives in the sign-in sheet, which already cancels the request server-side.
- **`dismiss` refuses a sign-in prompt at the server.** The shipped TestFlight build (1.3.0) renders any prompt with the old panel, whose Dismiss sends Escape to the pane; on a sign-in prompt that would interrupt the agent's waiting command. Rather than wait for a new client build, the one choke point (`POST /api/sessions/:id/dismiss`) returns 409 when the session's latest journaled prompt is `phone-sign-in`.
- **The panel's button prefers the polled request row, else the requests sheet.** `SessionDetailView` polls the request list every 3s; the prompt panel arrives via the journal sooner. When the row is present the button opens the sign-in view directly; otherwise it opens the requests sheet with that id, which auto-opens the request (one extra Done tap after cancelling — existing behaviour of that sheet).
- **Deploy requires a server restart**, which drops in-memory session tracking. Done as part of this task because the running process (started 00:03 today) predates every change here; a fix without a restart is the "deploy gap" the project CLAUDE.md warns about.

## Verification Evidence

Deployed to the Pro host 2026-09-16 21:32 local (pid 7055), redeployed 21:34 (pid 10084) after the stitcher fix below. Live probes target this session (c3fb2542) with `https://example.com/login` and the connected `Chrome — personal` target; every request was cancelled afterwards.

| SC | Command / action | Observed | Artifact |
| --- | --- | --- | --- |
| SC1 | `bun test src/phone-sign-in-requests.test.ts` (new `phoneSignInPrompt` test: waiting → prompt; cancelled/expired/delivering/other session → null; no cookie material in the prompt) | 8 pass, 0 fail | test file |
| SC1 | `resolveSessionPrompt` order: transcript prompt → pane prompt → sign-in fallback (`src/commands/serve.ts`); watcher `observeSession` mirrors it | code + tsc 0 errors | `src/commands/serve.ts`, `src/push/watcher.ts` |
| SC2 | `bun src/cli.ts browser-sign-in request --session c3fb2542… --target <chrome> --url https://example.com/login --no-wait`, then `GET /api/sessions` | `prompt: {"source":"phone-sign-in","question":"Sign in to example.com on your iPhone","header":"Sign in","options":[],"signIn":{requestId,url,website,targetName,expiresAt}}` — no `context` key after the stitcher fix | probe output in transcript |
| SC2 | `GET /api/session-states` | `{"needsInputSessionIds":["c3fb2542-…"]}` | probe output |
| SC2 | `sqlite3 ~/.lfg/journal.db` prompt rows for the session after the request | exactly 1 `prompt` row (seq 1025673) for the second request; the first request had produced 3 rows in 4s because the pane stitcher kept changing `context` — fixed, see Bugs | journal |
| SC2 | iOS list (sim, iPhone 17 Pro, host 127.0.0.1:8766) | session grouped under **Needs you** with the orange dot; header `Needs you, 1` in the accessibility tree | `evidence/phone-sign-in-needs-input/01-detail-sign-in-panel.jpg` (list state in transcript tree dump) |
| SC3 | `bun test src/push/watcher.test.ts` — new `reduceTransition — prompt while busy` (5 tests) + `runPushTick — phone sign-in request` | 73 pass in file; sign-in prompt appearing while busy → one `needs-input` push whose body is the question; retraction emits nothing | test file |
| SC3 | Live: `/private/tmp/lfg-serve.log` after `[push] watcher started` | one alert fan-out per request (visible as the 4 `DeviceTokenNotForTopic` failures among 99 registered tokens; successes are not logged) | server log |
| SC3 | Live: `~/.lfg/liveactivity.log` | `decide … "rows":["c3fb2542:needsInput", …]` at 13:34:23Z (request 1) and 13:36:16Z (request 2) — the card shows the session as needs-input while the agent is busy | log |
| SC4 | `bun src/cli.ts browser-sign-in cancel <id>` then `GET /api/sessions`, journal, `/api/session-states` | prompt `null`, one `prompt: null` journal row, `needsInputSessionIds: []` | probe output |
| SC4 | iOS: Cancel in the sign-in sheet | request `cancelled`, prompt panel gone from the tree, `/api/session-states` empty | `03-after-cancel-panel-gone.jpg` |
| SC5 | `swift test --package-path ios/LFGCore --filter ModelsTests` | 15 pass incl. `testAgentPromptDecodesSignInRequest` (signIn decoded; plain prompt has nil signIn) | test file |
| SC5 | Simulator: open the session while the request waits | panel shows "Needs your input · SIGN IN", the question, "The login is sent to Chrome — personal on your Mac. The agent is waiting.", one **Sign in to example.com** button (`prompt_sign_in_<id>`), no numbered options, no Dismiss; the composer's duplicate "Sign in to example.com" row is hidden | `01-detail-sign-in-panel.jpg` |
| SC5 | Tap the button | "Sign in on Phone" sheet opens on example.com with "I'm signed in" | `02-sign-in-sheet-opened-from-panel.jpg` |
| SC5 (old client) | `POST /api/sessions/c3fb2542…/dismiss` while the sign-in prompt is live | `409 {"error":"this prompt is a phone sign-in request — cancel it from the sign-in sheet"}` — a shipped TestFlight build that still offers Dismiss cannot send Escape into the waiting command | probe output |
| SC6 | `NODE_ENV=test bun test src/push src/journal-pump.test.ts src/journal.test.ts src/session-state.test.ts src/session-state-parity.test.ts src/phone-sign-in-requests.test.ts src/browser-sign-in.test.ts src/browser-sign-in.integration.test.ts src/sessions-status.test.ts src/sessions-queue-operation.test.ts src/tmux-prompt.test.ts src/sendq.test.ts src/hook-state.test.ts` | 255 pass, 0 fail, 18 files | scratchpad `bun-test-subset.log` |
| SC6 | `bunx tsc --noEmit -p .` | 0 errors | — |
| SC6 | `swift test --package-path ios/LFGCore --filter "ModelsTests|SessionDisplayStateTests|PromptPreambleTests|PhoneSignInTests"` | all pass | — |
| SC6 | `flowdeck build` / `flowdeck run` (iPhone 17 Pro) | BUILD succeeded 13:36:03Z; app launched | `scratchpad/flowdeck-build.log` |
| Audit | `verification-auditor` (independent; one request of its own, cancelled) | **PASS** on SC1–SC6. Re-ran tests (95/95, tsc 0, swift 15/15); live: prompt keys exactly `[header, options, question, signIn, source]`, one journal row, dismiss 409, cancel → null in one row; sim panel + sheet re-verified; Live Activity needsInput row at 13:51:41Z. Flagged one reducer edge (fixed below) and the pre-existing 92s Live Activity lag. | `evidence/phone-sign-in-needs-input/auditor/evidence.md` (25 artifacts) |
| TestFlight | `bundle exec fastlane ios deploy_testflight` from the main tree (2026-09-16 23:29) | build `202609162329` on train 1.3.0 uploaded; `verify_testflight_build`: ipa ground truth OK (CFBundleVersion=202609162329, v1.3.0), VALID after 3 polls, highest train, internal=IN_BETA_TESTING — DoD PASS 23:35 | `ios/fastlane/deploy-202609162329.log`, `ios/fastlane/verify-202609162329.log` |
| Post-audit | `bun test src/push` after the dedupe fix; redeploy | 97 pass, 0 fail; server restarted with no `waiting` requests on the host | — |

## Bugs

- **Fixed — pane preamble stitched onto the sign-in prompt.** `withStitchedPreamble` (`src/journal-pump.ts`) treated any prompt with a `question` as pane-scraped and attached the reconstructed pane as `context`; for a busy session that text changes every tick, so the first live request journaled three prompt events in four seconds and the REST prompt carried the agent's own command output. Guard now skips `source: "phone-sign-in"`. Verified: second request produced exactly one journal row and no `context` key.
- **Fixed — needs-input swallowed by the dedupe window was lost for good (auditor finding).** With the new prompt-first reducer, a prompt appearing within 10s of a previous push was suppressed *and* recorded as seen, so it could never "appear" again and the later busy→idle stays silent by design. `reduceTransition` now leaves a swallowed needs-input unrecorded so the next tick retries it once the window has passed; test extended (`… deduped …, then retried`).
- **Found, pre-existing, not fixed here — needs-input pushes never fired for AskUserQuestion.** With hooks installed a parked question keeps `busy` true, and the reducer returned early on busy; journal evidence (10 most recent transcript prompts) shows each was answered before busy ever dropped. The reducer change in this feature fixes it as a side effect. Logged in the decision log.
- **Found, pre-existing, not fixed — push tick fan-out.** One alert push loops sequentially over 99 registered device tokens; the tick that observed request 2 finished ~70s later. Logged in the improvement log.
