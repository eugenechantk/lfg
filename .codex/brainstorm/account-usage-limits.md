# Account usage limits in LFG

Feasibility checked on 2026-10-20. This note describes a proposed feature. No product code changed.

## Recommendation

Add **Usage limits** to the session list menu. Open a sheet with one section per provider and account. Show the account label, host, percentage used, reset time, and last update time.

Call the short quota **Current window** and show its duration. Quotas belong to the account and can span many LFG conversations. Context-window usage is a separate measure.

## Available data

### Codex

OpenAI documents `account/read`, `account/rateLimits/read`, and `account/rateLimits/updated` in the app-server protocol. Quota windows contain `usedPercent`, `windowDurationMins`, and `resetsAt`. The response can contain several metered buckets.

Live verification used the installed Codex 0.163.0 through a temporary app-server process. It issued only initialization and account read requests. No model turn or thread operation ran.

The local CLI login identified itself as ChatGPT Pro. Its response contained a weekly window: duration 10,080 minutes, 1% used, reset timestamp 1793072434. It returned no second window. This verifies that weekly data is available for this login. It does not establish the account used by every running session.

Do not assume `primary` means five hours or `secondary` means weekly. Classify each window by its reported duration. An absent window must say unavailable or be omitted; it must not show 0%.

The existing daemon socket was unavailable. A temporary app-server process successfully returned the data, so it provides a viable read path without opening a conversation.

Source: https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt

### Claude Code

Anthropic documents status-line JSON fields for `rate_limits.five_hour` and `rate_limits.seven_day`. Each includes `used_percentage` and `resets_at`. These fields appear after an API response for eligible subscriptions and can be independently absent.

Prefer collecting these documented fields from a status-line integration. Preserve any existing status-line output. Cache the latest observation with its account and session provenance. Explain when no recent observation exists.

LFG already exposes `GET /api/claude/usage`, but it reads a fixed credentials file and calls an OAuth usage endpoint. A live request to this Mac's LFG server returned HTTP 502 because the upstream returned 401. Existing Claude retrieval therefore needs updating. This does not prove Claude Code itself is signed out.

Source: https://code.claude.com/docs/en/statusline#rate-limit-usage

## Existing integration points

- `src/commands/serve.ts`: Claude usage route and its 60-second cache.
- `src/codex-app-server.ts`: existing app-server protocol helpers.
- `ios/LFGCore/Sources/LFGCore/Models.swift`: Claude-only usage types.
- `ios/LFGCore/Sources/LFGCore/LFGClient.swift`: Claude usage request.
- `ios/LFG/SessionStore.swift`: usage loads from one metadata host today.
- `ios/LFG/SessionListView.swift`: session list menu.
- `desktop/SessionsListS2.swift`: desktop list menu.

## Implementation boundaries

Fetch usage per host and account. Deduplicate only when account identity is reliable. Show a host label when identity cannot be established. Respect alternate credential homes and API-key authentication. API billing must not appear as an invented subscription quota.

Keep credentials on their host. Return normalized usage and account labels to clients. Refresh on opening the sheet and reuse a short cache. Show errors, stale observations, and absent windows explicitly.

Verify parser behavior for weekly-only responses, missing windows, account changes, reset expiry, and provider errors. Then verify the menu and sheet on iPhone, iPad, and macOS before release.
