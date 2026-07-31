# Improvement Log — Session 20260713-live-activity

## Tracker

- [ ] 2026-07-13 — Clarified a likely user misconception: Live Activities do NOT hold the host connection open; the server-side watcher + APNs push is what keeps state live when app is backgrounded/locked. Count of activities (N vs 1) is irrelevant to liveness.
- [ ] 2026-07-13 — codex delegation failed at launch: a broken repo-local `node_modules/.bin/codex` shim (transitive dep of `ai-sdk-provider-codex-cli`, vendor binary never downloaded) shadowed the working global codex. Cost one failed rescue + diagnosis. Candidate memory.
- [ ] 2026-07-13 — Codex delegation (per brief) explicitly did NOT build the iOS app target, so a name-collision compile error (`accentColor(for:)` vs SwiftUI `View.accentColor`) reached my verification. Brief told Codex not to build the app; that's correct division (Claude owns FlowDeck build), but means the app-target compile is entirely on the verification pass — budget for it.
- [ ] 2026-07-13 — Shipped the widget with 4pt padding (content flush to container edges); Eugene caught it. Root cause: while fixing height-budget clipping I tightened padding to 4pt and never re-compared against the mockup's 16pt — I was verifying "does it clip" not "does it match the mockup spacing." Lesson: when a UI is derived from a mockup, diff the final render against the mockup for spacing/padding, not just correctness/clipping.
- [ ] 2026-07-13 — Lock-screen Live Activity height budget (~160pt) silently center-clips overheight content, DROPPING THE HEADER (not the bottom). Only caught by screenshot (content isn't in the sim a11y tree). Header + 3 rows + overflow was too tall → header top clipped + "+N more" gone. Fixed by capping lock screen at header + 2 rows + overflow. Candidate memory / project CLAUDE.md note.

- [ ] 2026-07-13 — WidgetKit self-updating text (`Text(timerInterval:)`, `Text(_, style:.relative)`) reserves width for its WIDEST possible value → short values float left of their box ("offset from the right edge"). Fix: `.multilineTextAlignment(.trailing)` to right-align glyphs in the reserved box. Do NOT use `.fixedSize()` (reserves huge width, pushed rows out of frame) or `.layoutPriority` (stole width, collapsed the summary) — both caused regressions this session. Also: the `.relative` updated-time was low-value clutter fighting for header width; removing it was the clean fix.

- [ ] 2026-07-13 — Worktree TestFlight deploy failed first attempt: copied `fastlane/.env.default` (secrets) into the worktree but NOT `fastlane/.env` — which is gitignored in THIS repo (contrary to the skill's "committed .env" assumption) and holds `EXTENSION_TARGETS`. Missing it → widget extension got no match profile → archive failed "Embedded binary is not signed with the same certificate as the parent app." Lesson: a fresh worktree/checkout deploy must restore ALL gitignored fastlane env files (`.env` AND `.env.default`/`.env.local`), not just the secrets. Verify `git check-ignore fastlane/.env` before assuming it's committed.

## Log

### 2026-07-13 — Live Activity "keeps connection alive" misconception

**What happened:** User asked whether a single consolidated Live Activity still "keeps connection to hosts alive when app is in background/locked."
**Reality (from `src/push/watcher.ts`):** The always-on server watcher polls sessions every 2s and pushes start/update/end via APNs, entirely independent of any client SSE connection ("notify when the app is closed" is the module's stated purpose). The Live Activity is a render surface updated by remote push, not a socket the app holds open. So consolidating N→1 changes nothing about liveness — arguably cleaner (1 update token vs N).
**Why worth noting:** If the user believes activity count affects connection liveness, future design decisions could be skewed. Corrected explicitly.
