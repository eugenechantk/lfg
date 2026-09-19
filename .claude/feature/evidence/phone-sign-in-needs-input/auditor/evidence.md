# Verification Audit

Verdict: PASS
Timestamp: 2026-09-16 21:58 +0800
Repository: /Users/eugenechan/dev/personal/lfg
Surface: mixed (api + cli + iOS simulator + unit tests)

## Change Audited

A `waiting` phone sign-in request (`lfg browser-sign-in request …`) is synthesized into the session's `prompt` (`phoneSignInPrompt`, `source: "phone-sign-in"`), so the session grades needs-input on every surface that already consumes `prompt` (journal delta, `GET /api/sessions`, `GET /api/session-states`, push watcher, Live Activity). `reduceTransition` now emits `needs-input` when a prompt appears even while busy. `POST /api/sessions/:id/dismiss` returns 409 for a sign-in prompt. iOS renders a sign-in panel (`PromptPanelView` sign-in variant, `AgentPrompt.signIn`).

Server under test: pid 10084, `bun run src/cli.ts serve`, started 2026-09-16 21:34:46 local (after every touched file's mtime). Not restarted by the auditor.
Live probe: exactly ONE request created (`e0749198-4338-4af1-aa06-b5ac5ace7d4f`) for session `c3fb2542-12bb-483c-bb0e-bea79fe624bb`, url `https://example.com/login`, target `b60cd408… Chrome — personal`; cancelled via CLI at 21:54:19. No other session's requests were touched (verified: zero `waiting` requests anywhere before and after).

## Success Criteria

| Criterion | Declared Method | Result | Evidence |
|---|---|---|---|
| SC1 waiting request → prompt via `resolveSessionPrompt`; real prompt wins | unit test `phoneSignInPrompt` + serve-level resolution test | PASS (helper: unit test; live: prompt reached the snapshot). Precedence "real prompt wins" is covered by code inspection only — no serve-level test exists (`resolveSessionPrompt` and `observeSession` are module-private and untested); see Notes | `01-bun-test.log` (95 pass), `06-sc2-sessions-waiting-prompt.json` |
| SC2 prompt in REST snapshot + journal delta → needsInput | live probe | PASS. `/api/sessions` prompt `{source, question, header, options: [], signIn{requestId,url,website,targetName,expiresAt}}`, keys exactly `['header','options','question','signIn','source']`, no `context`. `/api/session-states` = `["c3fb2542-…"]`. Journal: exactly 1 `prompt` row (seq 1025928) | `06-sc2-sessions-waiting.json`, `06-sc2-sessions-waiting-prompt.json`, `07-sc2-session-states-waiting.json`, `08-sc2-journal-waiting.log` |
| SC3 push watcher emits needs-input while busy | reducer + runPushTick unit tests; live: push / liveactivity.log | PASS. Unit: watcher.test.ts green. Live: `liveactivity.log` `decide … rows:["c3fb2542:needsInput"]` at 13:51:41Z + APNs update 200; serve log shows one alert fan-out cluster (4× `DeviceTokenNotForTopic` among 99 registered tokens) at the tick that observed seq 1025928. Successful alert sends are not logged, so the phone-side delivery is indirect | `01-bun-test.log`, `11-sc3-liveactivity-waiting.log`, `12-sc3-serve-log.log`, `12b-sc3-push-devices.log`, `04-reducer-edge-cases.log` |
| SC4 prompt retracts when request leaves waiting | unit test + live cancel | PASS. CLI cancel → `state: "cancelled"`; 4s later `/api/sessions` prompt `null`, `needsInputSessionIds: []`, journal exactly one `prompt: null` row (seq 1025929) — 2 rows total since baseline, no flapping; Live Activity back to `c3fb2542:working` at 13:54:22Z (3s after cancel). Dismiss while waiting → `409 {"error":"this prompt is a phone sign-in request — cancel it from the sign-in sheet"}` | `15-sc4-request-cancel.log`, `16-sc4-after-cancel.log`, `17-sc4-liveactivity-after-cancel.log`, `09-sc4-dismiss-409.log` |
| SC5 iOS sign-in panel: no numbered options, no Dismiss, button opens sheet | LFGCore decode test + simulator screenshot | PASS. `swift test --filter ModelsTests` 15 pass incl. `testAgentPromptDecodesSignInRequest`. Sim (iPhone 17 Pro, host 127.0.0.1:8766, existing build): panel shows "Needs your input · SIGN IN", question, target hint, one button `prompt_sign_in_e0749198-…`; accessibility tree has no `Dismiss`, no option rows, and the composer's duplicate sign-in row is absent (only `childSessionsComposerBar` below the panel). Tapping the button opened the "Sign in on Phone" sheet on example.com with `Cancel` / `I'm signed in`. After cancel the panel is gone | `03-swift-test.log`, `13-sc5-sim-panel-waiting.png`, `13b-sc5-sim-panel-tree.json`, `14-sc5-sim-sheet-from-panel.png`, `18b-sc4-sim-after-cancel-tree.log`, `19-sc4-sim-final-clean.png` |
| SC6 no regression in needs-input / finished push | bun test subset + swift test | PASS by declared method (95/95 in the 4 touched files, tsc 0 errors, swift 15/15). One behavioural edge found by adversarial review — see Notes (not covered by any test, not exercised live) | `01-bun-test.log`, `02-tsc.log` (empty = 0 errors), `03-swift-test.log`, `04-reducer-edge-cases.test.ts` + `.log` |

## Artifacts

All under `/Users/eugenechan/dev/personal/lfg/.claude/feature/evidence/phone-sign-in-needs-input/auditor/`:

- `01-bun-test.log` — 4 touched test files, 95 pass / 0 fail
- `02-tsc.log` — empty output, exit 0
- `03-swift-test.log` — LFGCore ModelsTests, 15 pass
- `04-reducer-edge-cases.test.ts`, `04-reducer-edge-cases.log` — throwaway auditor test (8 pass) proving the existing rules and the two edge cases below
- `05-request-create.log` — CLI create output (request id, journal head 1025927 before)
- `06-sc2-sessions-waiting.json`, `06-sc2-sessions-waiting-prompt.json` — full snapshot + extracted prompt/keys
- `07-sc2-session-states-waiting.json`
- `08-sc2-journal-waiting.log` — 1 prompt row (seq 1025928)
- `09-sc4-dismiss-409.log` — full HTTP response
- `10-sc5-sim-waiting.png` — sim as found (requests sheet left open by the implementer, my request "Waiting for sign-in")
- `11-sc3-liveactivity-waiting.log`, `12-sc3-serve-log.log`, `12b-sc3-push-devices.log`
- `13-sc5-sim-panel-waiting.png`, `13b-sc5-sim-panel-tree.json` — the panel + filtered accessibility tree
- `14-sc5-sim-sheet-from-panel.png` — sheet opened by the panel button
- `15-sc4-request-cancel.log`, `16-sc4-after-cancel.log`, `17-sc4-liveactivity-after-cancel.log`
- `18-sc4-sim-after-cancel.png`, `18b-sc4-sim-after-cancel-tree.log`, `19-sc4-sim-final-clean.png`, `19b-sc4-sim-final-tree.log`

## Commands

```
cd /Users/eugenechan/dev/personal/lfg
NODE_ENV=test bun test src/push/watcher.test.ts src/phone-sign-in-requests.test.ts src/journal-pump.test.ts src/session-state-parity.test.ts
bunx tsc --noEmit -p .
swift test --package-path ios/LFGCore --filter ModelsTests
NODE_ENV=test bun test .claude/feature/evidence/phone-sign-in-needs-input/auditor/04-reducer-edge-cases.test.ts

curl -s http://127.0.0.1:8766/api/browser-sign-in/targets     # b60cd408-… "Chrome — personal"
/Users/eugenechan/.bun/bin/bun src/cli.ts browser-sign-in request --session c3fb2542-12bb-483c-bb0e-bea79fe624bb --target b60cd408-469d-45b7-a4ba-f0119e030f22 --url https://example.com/login --no-wait
curl -s http://127.0.0.1:8766/api/sessions                    # prompt for the sid
curl -s http://127.0.0.1:8766/api/session-states
sqlite3 ~/.lfg/journal.db "select seq,ts,type,substr(payload,1,400) from events where sessionId='c3fb2542-12bb-483c-bb0e-bea79fe624bb' and type='prompt' order by seq desc limit 3"
curl -s -i -X POST http://127.0.0.1:8766/api/sessions/c3fb2542-12bb-483c-bb0e-bea79fe624bb/dismiss -H 'content-type: application/json' -d '{}'
grep '"t":"2026-09-16T13:5' ~/.lfg/liveactivity.log
grep -n '\[push\]' /private/tmp/lfg-serve.log | tail
/Users/eugenechan/.bun/bin/bun src/cli.ts browser-sign-in cancel e0749198-4338-4af1-aa06-b5ac5ace7d4f

cd ios && FLOWDECK_UI_SKIP_LOCK_CHECK=1 flowdeck ui simulator screen --simulator E0DC8228-3248-4630-8929-FBC5DFC6AE6D --output <png> --json
cd ios && FLOWDECK_UI_SKIP_LOCK_CHECK=1 flowdeck ui simulator tap "prompt_sign_in_e0749198-4338-4af1-aa06-b5ac5ace7d4f" --by-id --simulator E0DC8228-…
```

## Notes

- **Reducer edge (SC6, judgement call — flagged, not failed).** With the busy gate removed, a prompt that appears while busy is announced immediately, and the later busy→idle is deliberately silent. If that appearance falls inside the 10s dedupe window after a previous push (e.g. `finished` → user replies → question within 10s), the candidate is dropped but `promptPresent` is still carried, so nothing ever fires for that question — including when the session later goes idle with the prompt still up, where the OLD reducer would have emitted `needs-input`. Same shape for a session seeded at startup as (busy, prompt): idle-with-prompt used to push, now does not. Proven by `04-reducer-edge-cases.test.ts` (the two `EDGE` cases assert `null` and pass). The old reducer had the equivalent hole for prompts appearing while idle, and with hooks installed busy does not drop until the answer, so real-world exposure is narrow. Suggest a follow-up: keep a "prompt announced" bit separate from `promptPresent` so a deduped appearance can be re-tried on a later tick.
- **Live Activity latency (pre-existing).** The needsInput LA row landed 92s after the request; the working row landed 3s after cancel. The difference is the alert push fan-out: the tick that emits a push loops sequentially over 99 registered tokens (95 sandbox tokens fail `DeviceTokenNotForTopic` or time out), and the LA decision runs after that loop in the same tick. Already noted by the implementer as a pre-existing issue.
- **Alert push delivery is indirect.** Only failed APNs sends are logged; the 200 to the real phone cannot be shown from logs. Evidence is the reducer/runPushTick tests plus the send-loop failure cluster at the right tick.
- **SC1 precedence ("real prompt wins") is not covered by a test.** `resolveSessionPrompt` (serve.ts) and `observeSession` (watcher.ts) are module-private; the diff orders transcript → pane → signIn in both, but no serve-level test exercises it, and I could not stage a real AskUserQuestion on the target session without disturbing the implementer's live session.
- **Out of scope, observed:** after a server-side cancel the open "Sign in on Phone" sheet stayed up on the sim until Cancel was tapped, then fell back to the requests-list sheet (one extra Done). Consistent with the decision-log note on the fallback path.
- `promptStatedAt` is `null` on `/api/sessions` both before and during the request — pre-existing, unrelated to this change.
- Simulator left on the session detail view with no sheet open; no FlowDeck capture session was running. Server not restarted. No source files modified.
