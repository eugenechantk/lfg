# Design brief: account usage limits

Eugene asks: “Lets get claude code to design the interface and let me review before implementation.”

You are the Claude Code designer for this task. Deliver a concrete visual proposal for review. Stop before product implementation.

## Ownership

You own only `.codex/design/account-usage-limits/design.md`, `preview/index.html`, and new supporting design files under `.codex/design/account-usage-limits/reference/`.

You are not alone in this codebase. Preserve all existing changes. Do not modify app code, backend code, project files, settings, credentials, real account state, or tasks. Do not commit, push, release, deploy, start servers, or send messages outside this task. Do not build the native apps. The parent will publish and review your HTML preview. Do not create unrelated workflow logs.

## Goal and constraints

Add a **Usage limits** option to the existing session list menu. It opens a focused native interface showing Claude Code and Codex account limits: current quota window, weekly window, percentages used, reset times, last update, and provider/account/host identity.

Read `.codex/brainstorm/account-usage-limits.md` for the verified data contract. Important:

- These quotas apply to the account across conversations. They are not context-window fullness or token spend for one conversation.
- Codex reports windows dynamically. The live CLI account returned only a weekly window. Missing short-window data cannot look like 0% used.
- Claude may have no observation until an API response. Retrieval failure does not prove the account needs to sign in again.
- Different hosts may use different accounts. The same account across Pro and Air must not look like two independent quotas. Do not merge identities without proof.
- Treat identity, stale data, no data, refresh progress, offline hosts, near/exhausted quotas, and API billing as honest design states.
- Mock values and identities must be visibly labeled as samples. Do not fetch real credentials or quote real email addresses.

## Existing design language

Read these sources selectively before designing:

- `.claude/feature/sessions-redesign-s2.md`: opening design/component sections.
- `ios/LFG/SessionListView.swift`: the S2 tokens, toolbar and `moreMenu`.
- `desktop/SessionsListS2.swift`: S2Desk tokens and host strip menu.
- `ios/LFG/NewSession/NewSessionTheme.swift` and `NewSessionSheets.swift`: sheet patterns.
- `.codex/design/retry-later/design.md`: recent sheet and light/dark decisions.
- `.codex/design/account-usage-limits/hig-sheets.txt` and `hig-gauges.txt`: current Apple guidance fetched for this task.

The existing **LFG UI Map** canvas is https://claude.ai/artifact/F2B1MNbv5oxuscm237M9sD. If the native Artifact tool is available, inspect it, reuse its components, and add a new page **Usage limits (Oct 20)** with uniquely prefixed `usage-*` boards. Keep every existing board and page untouched. Use the incremental publish workflow against a fresh canvas version; re-read to verify persistence. Export your exact new board sources into `reference/` and record the version/page/board IDs. Do not use the obsolete claude-design MCP server or create a replacement canvas. If native Artifact access is unavailable, say so and still finish the standalone HTML preview; do not stall or invent canvas changes.

## Deliverables

1. `design.md`: recommend one design direction, grounded in existing LFG components. Specify menu placement, presentation on phone/iPad/Mac, account grouping, quota rows and labels, reset copy, refresh behavior, warning thresholds, empty/error/stale states, keyboard and accessibility behavior. Include concise dimensions and token mappings. Explain material tradeoffs. Do not expand into implementation or a new analytics dashboard.
2. `preview/index.html`: a polished, self-contained, responsive HTML design review page. Use CSS, inline SVG and system fonts only. Include a visible **Design proposal · Sample data** label. Show the phone list menu entry, normal phone usage sheet, a weekly-only Codex state, stale/error/exhausted states, iPad adaptation, and a compact Mac view. Include dark and light themes. Provide working theme and scenario controls so Eugene can inspect the states. Use meaningful labels and real buttons; support keyboard and narrow phone review. Keep all explanatory text brief. This is a mockup for review, never runtime evidence. No external assets or dependencies.

Prefer calm native hierarchy, readable percentages, compact reset information, and one clear refresh action. Match LFG rather than inventing a visual system. You choose the design; the parent will not replace it with its own design.

Return the paths, your recommendation, and canvas details or the exact unavailable capability. Do not ask Eugene questions. The parent will show him the finished proposal and wait for approval before implementation.
