# Feature: Child agent sessions

## User Story

As an LFG user viewing a session, I want to see the child agents that the session
spawned, inspect their state, and open each child transcript without leaving the
parent conversation.

As an LFG user scanning the session list, I also want the parent row to disclose
active child and shell work and remain in **Working** while any child agent or
background process is running.

## User Flow

1. Open a parent session that has spawned child agents.
2. See a compact child-session strip directly above the message composer.
3. Tap the strip to open a sheet listing all child sessions and their current state.
4. Alternatively, open the session's More menu, expand **Child sessions (N)**, and
   choose either **View all** or a named child.
5. Tap a child row—or choose it directly in More—to push its read-only transcript
   inside the sheet.
6. Dismiss the sheet to return to the unchanged parent conversation.
7. Return to the session list while a child is active; the parent appears in
   **Working** and its subtitle shows compact icon counters for active child agents
   and background shell processes.

## Success Criteria

- [x] SC1: Claude child agents are discovered from the parent transcript and its
  `subagents` sidecar directory, with description, type, lifecycle state, timestamps,
  and a stable internal identifier.
- [x] SC2: A parent with children shows a compact child-session control immediately
  above the composer; a parent without children renders exactly as before.
- [x] SC3: Tapping the above-composer control opens a sheet containing every child,
  ordered by most recent activity, with running/completed/failed/stopped state.
- [x] SC4: The parent session's More menu includes a **Child sessions (N)** submenu
  containing **View all** plus every named child; either route opens the same sheet at
  the expected list or child transcript.
- [x] SC5: Tapping a child pushes a read-only child transcript within the sheet.
- [x] SC6: Child lifecycle and transcript content refresh while the parent detail is
  open. Collection summaries and launch receipts do not expose raw launch prompts,
  temp paths, or opaque IDs; the child transcript intentionally shows its conversation.
- [x] SC7: Existing parent transcripts, composer behavior, and sessions without child
  agents are unchanged.
- [x] SC8: A live parent session reports `runningChildAgentCount`, and its canonical
  `busy` value remains true whenever at least one discovered child is running—even if
  the parent's own turn is idle. — **Verify by:** Bun aggregation tests and API probe.
- [x] SC9: A session-list row uses an SF Symbol plus count for active children instead
  of a long sentence; zero active children add no token. VoiceOver still announces
  grammatically correct copy. — **Verify by:** LFGCore presentation tests and
  Simulator audit.
- [x] SC10: Claude background Bash tasks are counted from launch/terminal lifecycle
  records, and Codex background terminals are counted from its live pane status.
  Completed, failed, or stopped processes do not count. — **Verify by:** Bun parser
  tests using real transcript and pane shapes.
- [x] SC11: A background process exposes `runningBackgroundProcessCount`, adds its own
  terminal-symbol counter, and keeps the parent canonically busy even when its main
  turn is idle. — **Verify by:** Bun aggregation/push tests, Swift decoding tests, and
  Simulator audit with distinct child/process counts.

## Test Strategy

- Bun unit tests cover sidecar discovery, lifecycle event reduction, ordering,
  redaction, malformed/missing files, and child transcript resolution.
- LFGCore Swift tests cover lenient API decoding and presentation summaries.
- Server aggregation tests cover active-child counts and parent busy-state promotion.
- Server parser tests cover Claude background-task lifecycle and Codex pane counters.
- LFGCore presentation tests cover zero/singular/plural accessible counter copy.
- Simulator verification covers both entry points, sheet presentation, child-row
  navigation, placement above the composer, and unchanged no-child state.

## Tests

### Server unit

- `src/subagents.test.ts`
  - discovers metadata and transcript sidecars (SC1)
  - reduces newest completed/failed/killed/stopped/running notification (SC1, SC6)
  - orders by last activity descending (SC3)
  - ignores malformed paths/files and never returns raw prompt/temp-path copy (SC6)
  - resolves only child transcripts belonging to the requested parent (SC5, SC7)
  - folds running children into the parent count and canonical busy state (SC8)
  - counts live background processes and folds them into canonical busy state (SC10-SC11)

### LFGCore unit

- `ios/LFGCore/Tests/LFGCoreTests/ChildAgentSessionTests.swift`
  - leniently decodes summaries and response defaults (SC1, SC7)
  - maps server states to compact count/status presentation (SC2-S4)
  - formats zero/singular/plural accessible child/process counter copy (SC9, SC11)
- `ios/LFGCore/Tests/LFGCoreTests/ModelsTests.swift`
  - decodes both running-work counts leniently and defaults older hosts to zero (SC8, SC11)

### Runtime UI

- Parent with fixture/live child agents: assert strip placement, More-menu action,
  sheet list, state labels, and pushed child transcript (SC2-S6).
- Parent without children: assert no strip or menu entry and normal composer (SC7).
- Parent with active children and background processes: assert the row is in **Working**
  and its subtitle shows distinct child-agent and terminal icon counters (SC8-SC11).

## Implementation Details

- Server-derived read model; the client does not parse Claude JSONL.
- The server enriches the canonical session snapshot after deduplication: running child
  agents and background processes contribute their own counts and both promote `busy`,
  so REST, the journal, push/Live Activity, and every client share the same parent status.
- Claude lifecycle records identify background-task candidates, while one batched `lsof`
  probe per session-list snapshot proves which output files still have live writers. This
  prevents missed terminal notifications from pinning a parent in **Working** without
  recreating a per-session process-spawn fan-out.
- Read-only child transcript view. Direct child steering remains owned by the parent
  agent because Claude's internal child protocol is not an independently addressable
  LFG session API.
- `.sheet(item:)` owns presentation. A `NavigationStack` inside the sheet owns child
  transcript navigation.
- Refresh summaries on detail entry and on a short foreground interval while children
  are running; completed histories remain stable.
- Native `Menu`, `sheet`, `List`, `NavigationStack`, and `ProgressView` follow the HIG
  guidance for compact actions, scoped modal content, hierarchical browsing, and
  indeterminate work state.

## Decision Log

- Internal Claude sidechains stay inside parent session detail rather than becoming
  top-level session rows; LFG's existing `parentSessionId` feature represents separate
  managed sessions and has different lifecycle semantics.
- The above-composer surface is one compact summary control, not horizontally scrolling
  child cards; it remains usable with large Dynamic Type and many children.
- Child detail is read-only for this version; sending through the parent is the only
  protocol-safe control path.
- The list shows only the active-child count. Terminal child history remains available
  in the detail sheet without lengthening every session-row subtitle.
- Child agents and shell processes stay separate: `person.2.fill` communicates delegated
  agents while `terminal` communicates shell work; each compact token is omitted at zero.

## Residual Risks

- Claude may change its sidecar layout; missing or malformed child metadata safely
  degrades to no child-session surface rather than breaking the parent session.
- Claude may add lifecycle status values; unknown values decode as a safe neutral state.
- Codex's background-terminal count comes from bounded composer chrome; if its TUI copy
  changes, the count safely falls back to zero instead of matching arbitrary agent prose.

## Verification Evidence

- Server: `bun test` passed (667 tests), including 9 focused child-agent discovery,
  lifecycle, API, and transcript-normalization tests.
- Core: `swift test` passed, including 4 child-agent decoding/presentation tests.
- Static/build: `bunx tsc --noEmit`, `git diff --check`, and `flowdeck build` passed.
- Runtime: isolated iPhone 17 Pro Simulator verified the above-composer strip, native
  child-session sheet, two stopped child rows, read-only transcript navigation, and the
  More-menu **View all** plus direct-child entry points against the real sidecar data
  from session `lfg-e6db43` through a read-only fixture host on port 8778.
- Independent visual audit: **PASS**. Evidence and the full report are in
  `.codex/evidence/20260820-132324-ios-visual-audit/`; the audit also confirmed that a
  no-child parent retains its normal composer and has no child-session More-menu item.
- Session-list extension: `bun test` passed (671 tests), `swift test` passed (96 tests),
  `bunx tsc --noEmit` passed, and `flowdeck build` passed. A current-source API probe
  on an isolated port confirmed all 34 live rows expose `runningChildAgentCount`; the
  real `lfg-e6db43` row safely reports zero now that its children are terminal.
- Runtime extension: isolated iPhone 17 Pro Simulator placed a synthetic idle-parent /
  active-child session in **Working** and visibly rendered `2 child agents running`.
  Screenshot and accessibility evidence live in
  `.codex/evidence/20260820-child-running-list/`.
- Independent session-list audit: **PASS**. The auditor confirmed the parent row is in
  **Working**, the child count is visibly legible, and its layout matches neighboring
  rows. Report: `.codex/evidence/20260820-133800-ios-visual-audit/evidence.md`.
- Final delegated-work counters: `bun test` passed (679 tests), `swift test` passed
  (96 tests), `bunx tsc --noEmit` passed, and `flowdeck build` passed. The Simulator
  fixture rendered compact `person.2.fill 2` and `terminal 1` tokens on an idle parent
  in **Working**; the accessibility tree exposed “2 child agents running” and
  “1 background process running”. Local evidence:
  `.codex/evidence/20260820-session-work-counters/`.
- Independent delegated-work counter audit: **PASS**. It confirmed the compact,
  visually distinct counters, full accessibility label, normal row layout, and the
  parent's **Working** placement against fixture counts. Report:
  `.codex/evidence/20260820-135126-ios-visual-audit/evidence.md`.

## Bugs

_None yet._
