# Feature: account usage survives provider rate limits

Bug fix for the shipped Usage limits sheet (original feature: `.codex/feature/account-usage-limits.md`).

## What was wrong (2026-10-28)

The Claude card showed "Couldn't update limits from Air, Pro · No reading yet" and the plan "Max 5×" (the account is Max 20×).

- **Pro:** `GET api.anthropic.com/api/oauth/usage` returns **429** with `retry-after` (a fixed hourly window: two probes six minutes apart both pointed at 04:59:00 UTC). Claude Code itself calls the same endpoint (`api/oauth/usage?at_wall=1`, `?cedar_ember=1`), and about 21 Claude sessions run on this account, so the account's budget runs out without lfg's help.
- lfg had **no memory across this**: the cache is in-memory, keyed by the access token (which rotates every few hours), with no negative caching and no use of `retry-after`. After a restart or a token rotation there is no last reading, so every request during the window re-hits the API and shows an empty error card.
- **Plan label:** the Air's server cannot read its Keychain (it runs outside the GUI session), so it falls back to the Syncthing-synced `~/.claude/.credentials.json`, which is expired (Oct 24) and says `default_claude_max_5x`. `~/.claude.json` (`oauthAccount.organizationRateLimitTier`) says `default_claude_max_20x` on both hosts.
- **Air, both providers:** the Air is on an iPhone hotspot in Hong Kong with every VPN disconnected. Anthropic answers 403 "Request not allowed" and chatgpt.com answers 403. This is the network, not lfg.
- **Codex "Current window · Not reported":** by design. ChatGPT Pro reports only a weekly window (design.md, "A missing window is never 0%").

## User Story

As Eugene, I want the Usage limits sheet to show my last known Claude usage and when it will update, so that a provider rate limit or a server restart does not blank the numbers.

## User Flow

1. Open Usage limits from the session list menu.
2. If the provider is rate-limiting usage reads, the card keeps the last reading (with its age) and says when the next check can happen.
3. Refresh during the limit does not call the provider again.

## Success Criteria

- [x] SC1: A 429 sets a hold until `retry-after`; reads during the hold do not call the provider and return `error: "rate_limited"` with `retryAt`. — **Verify by:** `bun test src/account-usage.test.ts` (hold test counts loader calls).
- [x] SC2: The last good reading per proven account survives a token rotation and a process restart (file store), and is returned with `status: "error"` and its original `fetchedAt` when a read fails. — **Verify by:** unit tests for rotation + new cache instance over the same store file.
- [x] SC3: A different account never inherits another account's stored reading; unproven readings are never stored. — **Verify by:** unit tests.
- [x] SC4: The Claude plan label comes from `~/.claude.json` `organizationRateLimitTier` before the credentials tier. — **Verify by:** unit test of the plan helper + live `curl /api/account-usage` on the Pro shows "Max 20×".
- [ ] SC5 (BLOCKED, external): The live Pro server, after restart, answers `/api/account-usage` with `error: "rate_limited"` + `retryAt` during the window, and with real windows once the window ends; the reading then survives a second restart. — **Verify by:** live curl before/after restart.
- [x] SC6: The Apple clients decode `retryAt` and say "<Provider> is limiting usage checks. Next check after <time>." — **Verify by:** Swift package tests (decode + copy helper).

## Platform & Stack

- Backend: Bun/TypeScript (`src/account-usage.ts`), tests with `bun test`.
- Clients: shared Swift (`ios/LFGCore`, `shared/Usage`).

## Steps to Verify

1. `bun test src/account-usage.test.ts` and `bunx tsc --noEmit -p .`
2. `swift test --filter AccountUsage` in `ios/LFGCore`.
3. Restart the Pro server by port; `curl -s 127.0.0.1:8766/api/account-usage`.

## Decision Log

- Hold key is the proven account (falls back to the credential key), so a token rotation does not escape a hold. The hold is not persisted: a restart costs one extra 429, which is cheap.
- Stored readings older than 8 days are ignored: the longest window is 7 days.
- No "blocked" error code for the Air's 403s: Codex's `account/read` fails with "workspace routing discovery failed", not a 403, so it cannot be detected reliably. The fix there is the VPN.
- Not changing the Codex placeholder row: it is the approved design.

## Verification Evidence

| SC | Command / action | Result |
|----|------------------|--------|
| SC1, SC2, SC3, SC4 | `bun test src/account-usage.test.ts` | 18 pass, 0 fail (7 new: retry-after parsing, hold without provider calls incl. rotated token, rotation keeps last reading, restart through file store, other account never inherits, unproven never stored, >8 days ignored, plan helper). `bunx tsc --noEmit -p .` 0 errors. |
| SC4 | `bun -e` calling `accountUsage()` on the Pro, then live `curl 127.0.0.1:8766/api/account-usage` after restart (pid 995 → 50822, 04:13 UTC) | `claude Max 20× error rate_limited 2026-10-28T04:59:00Z` (was "Max 5×"/"Max 20×" depending on host); codex `ok`, weekly 40%. |
| SC5 (first half) | same live curl | `error: "rate_limited"`, `retryAt` 04:59:00Z, matching Anthropic's `retry-after`. `~/.lfg/account-usage.json` written with the Codex reading. |
| SC6 | `swift test --filter AccountUsage` in `ios/LFGCore` | 13 pass, incl. `rateLimitedReadingSaysWhenTheNextCheckIs` (decode `retryAt`, copy before/after the hold, no "kept below" without windows, other errors unchanged). Desktop sources type-check with `swiftc -typecheck` (build.sh file list), exit 0. |

| SC5 (second half) | background curl at 05:00:36 UTC, after the 04:59 reset | **Blocked.** Still `rate_limited`, new `retryAt` 06:00:36Z = exactly now + 1 h. Other callers (Claude Code's own sessions) used the account's budget within 96 s of the reset. lfg's hold and storage work, but it may never win a call. |

Independent audit (verification-auditor, 04:20 UTC): PARTIAL. SC1–SC4, SC6 and the first half of SC5 PASS; second half of SC5 not in its scope. Evidence: `.claude/evidence/account-usage-rate-limit/evidence.md`.

## Blocker: the usage endpoint is starved

Anthropic's `/api/oauth/usage` budget is per account and Claude Code's ~20 sessions spend it within seconds of each hourly reset, so the endpoint cannot be lfg's primary source. Proposal (needs Eugene's OK, because it changes every Claude session's UI and the synced `~/.claude/settings.json`): a global `statusLine` command that writes the `rate_limits` field Claude Code passes to status lines (filled from its own API response headers, so free) to `~/.lfg/claude-rate-limits.json`; lfg reads that first and keeps the endpoint as a fallback. Checked: at startup, before any API response, the status line input has no `rate_limits` key (`context_window, cost, cwd, effort, model, session_id, ...`). Still to check: that it appears after the first response.

B1's fix is in the source but not deployed; it rides the next server restart.

## Bugs

- **B1 (auditor, fixed):** a failed Codex read served the stored reading for the account named in `auth.json` without re-proving the file store, so a stale `auth.json` after a move to Keychain storage could show the old account's reading. Fix: the account key is passed to the cache only when this credential context has proved `cli_auth_credentials_store = file`. Bun tests 18/18 and tsc clean after the fix; deployed with the SC5 restart.
