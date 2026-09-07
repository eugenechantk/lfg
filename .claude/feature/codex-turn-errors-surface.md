# Feature: codex-turn-errors-surface

## User Story

As the lfg operator, I want a codex session whose turn failed (usage limit exhausted, unsupported model, upstream 4xx) to show that error in the session view and read as "paused" in the list, so that a stalled codex build is an explained pause and not a silent stall I discover an hour later.

## Context (ground truth, 2026-09-07)

- Codex (0.153, the `~/.bun/bin/codex` install) records a failed turn ONLY as an `event_msg` with `payload.type: "task_complete"` and a `payload.error: { message, codex_error_info }` object. No assistant message, no standalone `error` event (zero `error` events in any Sep 5–7 rollout; the April `error` events were compaction stream hiccups, never paired with a `task_complete` error).
- Observed `codex_error_info` values across Aug–Sep rollouts: `usage_limit_exceeded` (4) and `other` (28). `other` messages seen: JSON-wrapped 400 "The 'gpt-5.4' model is not supported when using Codex with a ChatGPT account", JSON-wrapped 400 "The 'gpt-6-astra' model requires a newer version of Codex", "unexpected status 403 Forbidden: <html>…", "unexpected status 404 Not Found …", an MCP transport error.
- `normalizeCodexLine` (`src/sessions.ts`) handles `event_msg` `error` / `warning` / `turn_aborted` but lets `task_complete` fall through to `[]`. So the transcript shows nothing.
- `computeStatus` only classifies a message with `apiError` set; codex messages never set it. The codex list path also passes `previewLast` (last message of ANY role), so even a flagged message would be erased by the next user row — the exact latch the Claude path fixed in `.claude/diagnosis-stop-close-noop-20260806.md`.
- The two sessions that motivated this: rollouts `2026-09-06T20-41-19-01a076bc…` and `2026-09-07T01-32-52-01a077c7…`, both ending in `usage_limit_exceeded` ("…try again at 9:00 PM").

## User Flow

1. A codex session's turn fails upstream (usage limit).
2. The session view transcript shows the error text as the agent's last turn, marked with the orange "API error" label.
3. The session list shows the session as paused (not "Working", not idle), and the session view shows the orange "Build paused" banner with codex's own message (which contains the reset time).
4. The user tops up / waits, sends a new prompt, codex answers, and the banner clears on its own.

## Success Criteria

- [x] SC1: A codex `task_complete` event carrying `error` normalizes to an assistant text message with `apiError: true` and `errorCode` = `codex_error_info`; a `task_complete` without `error` still normalizes to nothing. — **Verify by:** `bun test src/sessions-codex-transcript.test.ts` (new cases).
- [x] SC2: `computeStatus` classifies the codex usage-limit error as `blocked` / `out_of_credits` with the codex message (reset time included) as `statusDetail`; the JSON-wrapped "model is not supported" / "requires a newer version" 400 as `model_unavailable` with the unwrapped message; any other codex turn error as `unknown` with the first line of the message. — **Verify by:** `bun test src/sessions-status.test.ts` (new cases).
- [x] SC3: The codex list path grades status from the last ASSISTANT message, so a user row appended after the error does not erase `blocked`. — **Verify by:** unit test driving `lastAssistantForTest` over a codex rollout fixture (error line followed by a user_message line).
- [x] SC4: Live: after restarting `lfg serve`, `GET /api/sessions` reports `status: "blocked"`, `statusReason: "out_of_credits"` for the two live usage-limited codex sessions, and their message stream includes the error message. — **Verify by:** `curl 127.0.0.1:8766/api/sessions` + the messages endpoint, output recorded below.
- [x] SC5: iOS `PausedBannerView` shows the server's `statusDetail` when present (so the codex message with the reset time is what the user reads), and only appends the "switch model" hint for `model_unavailable`. — **Verify by:** LFGCore/iOS build green via FlowDeck + a simulator screenshot of a blocked codex session's banner.
- [x] SC6: Existing suites stay green. — **Verify by:** `bun test`.

## Platform & Stack

- **Platform:** Backend (Bun/TypeScript) + iOS client (SwiftUI)
- **Language:** TypeScript, Swift
- **Key frameworks:** bun:test, SwiftUI, FlowDeck for the iOS build

## Steps to Verify

1. `bun test` in the repo root.
2. Restart the server by port (`lsof -nP -iTCP:8766 -sTCP:LISTEN -t | xargs kill`; `serve-forever.sh` respawns) and confirm the new process is younger than `src/sessions.ts`.
3. `curl -s 127.0.0.1:8766/api/sessions | jq '.sessions[] | select(.agent=="codex") | {sessionId,status,statusReason,statusDetail}'`.
4. FlowDeck build of `ios/LFG.xcodeproj`; open a blocked codex session; screenshot the banner.

## Implementation Phases

### Phase 1: Server — normalize + classify

- Scope: `normalizeCodexLine` emits the `task_complete.error` as an assistant `apiError` message; `computeStatus` learns the codex error vocabulary; codex list path uses `lastAssistantMsg`.
- Success criteria covered: SC1, SC2, SC3, SC6
- Verification gate: bun tests green.

### Phase 2: Client — banner text

- Scope: `PausedBannerView` prefers `statusDetail`.
- Success criteria covered: SC5
- Verification gate: FlowDeck build green + screenshot.

### Phase 3: Deploy + live probe

- Scope: restart the local server, probe the two real sessions.
- Success criteria covered: SC4
- Verification gate: recorded curl output.

## Decision Log

- **Error message is an assistant-role text with `apiError: true`, not a system `tool_result`.** Mirrors how Claude Code writes API errors, so the whole existing status contract (`lastAssistantMsg` → `computeStatus`) and the iOS "API error" label work unchanged. Alternative — reuse the `error` event's system/tool_result shape — would render but never block.
- **Only `task_complete.error` blocks; the standalone `error` event keeps its current non-blocking rendering.** The `error` events on record are transient stream/compaction hiccups codex retries on its own; flagging them would produce false "Build paused" banners.
- **No `apiErrorStatus` is derived for codex errors.** A codex "unexpected status 403 Forbidden" is a Cloudflare/HTML page from chatgpt.com, not an auth failure; routing it through the 401/403 → "run /login" branch would give wrong advice. Codex errors classify by `codex_error_info` + prose only.
- **HTML bodies are cut off at the first `<html`/`<!doctype`.** The 403 message embeds an entire HTML page; the transcript keeps the status line only.
- **`usage_limit_exceeded` maps to the existing `out_of_credits` reason** rather than a new enum value, so the desktop app (`status == "blocked"` → Paused) and the iOS banner work without a protocol change. The detail text carries the codex-specific wording.

## Verification Evidence

| SC | Command / action | Observed | Artifact |
| --- | --- | --- | --- |
| SC1 | `bun test src/sessions-codex-transcript.test.ts` — 4 new cases under "codex turn errors (task_complete.error)" | red before the change (3 fail, the no-error case already passed), green after | test file |
| SC2 | `bun test src/sessions-status.test.ts` — "computeStatus — codex turn errors" | usage limit → `blocked`/`out_of_credits`/full sentence; JSON-wrapped 400 → `model_unavailable` with unwrapped message; 404 → `unknown`; 403+HTML → `unknown` (not auth) | test file |
| SC3 | same suite, "selection: a later codex user row does not erase the block" — rollout fixture: error line then `user_message` line, graded via `lastAssistantForTest` | `out_of_credits` | test file |
| SC4 | killed listener pid 19381 (`lsof -nP -iTCP:8766 -sTCP:LISTEN -t`), `serve-forever.sh` respawned pid 84261 at 02:12:06 (source mtime 02:11); `GET /api/sessions` | sessions `01a076bc-…` (lfg-162d30) and `01a077c7-…` (lfg-62558a): `status:"blocked"`, `statusReason:"out_of_credits"`, `statusDetail:"You've hit your usage limit… try again at 9:00 PM."`; the other 5 codex sessions `status:"ok"`. `GET /api/sessions/01a077c7-…/messages?limit=3` tail = `{role:"assistant", apiError:true, errorCode:"usage_limit_exceeded", text:"You've hit your usage limit…"}` after the user row "Set up TestFlight for me" | this table |
| SC5 | `flowdeck build` (Debug, iPhone 17 Pro) → BUILD succeeded 02:12:48, binary newer than `Components.swift` (02:11:52); `flowdeck run -S BBC3AA46-…` on sim `cc-96d9e70f`, app auto-configured Pro+Air hosts via the bundled Access credential; tapped the Paused row | List: new "Paused 2" group holding exactly the two codex sessions (yellow dot). Detail: orange "Build paused — out of credits" banner with the codex sentence incl. "try again at 9:00 PM"; transcript shows the error as the assistant turn with the "API error" label under it | `evidence/codex-turn-errors-surface/01-list-paused-group.jpg`, `02-detail-banner.jpg` |
| SC6 | `bun test` → 763 pass, 0 fail, 65 files (13.3s); `bunx tsc --noEmit -p .` → 0 errors | green | this table |

Independent audit (verification-auditor): see `evidence/codex-turn-errors-surface/auditor-report.md`.

## Deploy note

Only the Pro host (`Eugenes-MacBook-Pro`) runs the new server code. The Air still runs the old `sessions.ts` until this is committed, pulled there, and its `serve` process restarted. Nothing has been committed.

## Bugs

_None yet._
