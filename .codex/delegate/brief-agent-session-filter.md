# Delegation Brief: agent-session-filter — tag worker sessions, fold them out of the list

**Goal:** orchestrator-spawned worker sessions ("sub-agents") stop cluttering the session
list. Creation gains an optional `parentSessionId`; tagged sessions carry it through the
API; the iOS list folds them into a collapsed **Agents** group at the bottom of the Status
view instead of interleaving with the user's own sessions. Untagged behavior is byte-for-
byte unchanged.

**Repo:** worktree of `lfg` (branch from current main). Bun + TS server, SwiftUI client
(Swift 6 strict). Allowed: `src/` (+tests), `ios/LFGCore/Sources/LFGCore/Models.swift`
(+tests), `ios/LFG/SessionStore.swift` (minimal), `ios/LFG/SessionListView.swift`,
`.claude/skills/lfg-sessions/SKILL.md` (doc example update). Nothing else.

## Context (read first)

- `src/managed.ts` — `ManagedSession` record + `addManaged`; managed-sessions.json is the
  natural home for the tag (keyed by tmuxName, like user assignments).
- `src/commands/serve.ts` — `POST /api/sessions/new` handler (find it; it already takes
  prompt/model/cwd/user...). Wire `parentSessionId` through to `addManaged`.
- `src/sessions.ts` — `listSessions` enrichment: rows must expose `parentSessionId` for
  managed sessions that have one (join by tmuxName, like `assignedUser` does — see the
  `assigns` pattern around line 1055).
- `ios/LFGCore/Sources/LFGCore/Models.swift` — `Session` lenient decoding; add
  `parentSessionId: String?` following the house pattern exactly.
- `ios/LFG/SessionListView.swift` — Status grouping (`groupedSections`, `ListSection`),
  and the Directory mode's collapsible-section mechanics (`expandedDirs`,
  `sectionHeader`) — REUSE that collapse pattern for the Agents group.
- `ios/LFG/SessionStore.swift` — `group(for:)` / `Group` enum if the cleanest cut is a
  new group case; keep changes minimal either way.

## Spec

1. **Server:** `POST /api/sessions/new` accepts optional `parentSessionId` (trimmed
   string, ≤64 chars; invalid → ignore, never fail creation). Persist on the managed
   record. `/api/sessions` rows include `parentSessionId` when present. Test: create with
   tag (unit-level against managed.ts + the listSessions join; HTTP test if the suite has
   precedent).
2. **Client model:** `Session.parentSessionId: String?`, lenient. Decode test.
3. **Client list:** in the STATUS grouping only, sessions with a non-nil parentSessionId
   leave their normal group and render in one **"Agents"** section, placed last,
   collapsed by default, expandable via the same chevron/header interaction Directory
   sections use (show a count in the header like Directory's tallies). Needs-input
   EXCEPTION: an agent session in `.needsInput` stays in "Needs you" (a blocked agent
   needs the human regardless of lineage). Directory mode: unchanged this pass.
   Detail view, search: unchanged (search still finds them).
4. **Skill doc:** update `.claude/skills/lfg-sessions/SKILL.md`'s "Start a new worker
   session" example to pass `"parentSessionId":"<your own sessionId>"` with one line of
   why.

## Verification

1. `bun test` green (+ new tests). `cd ios/LFGCore && swift test` green (+ decode test).
2. Build for sim via flowdeck if the sandbox allows; else say so.
3. State: exact JSON of a tagged row; what an untagged deployment renders (must be
   identical to today).

## Definition of done
- [ ] Tagged creation → row carries parentSessionId; untagged flows byte-identical.
- [ ] Status list: agents folded into collapsed last section; needs-input exception.
- [ ] Lenient decode; suites green; skill doc example updated.

**Report back:** files changed, test output, the tagged-row JSON, deviations.
