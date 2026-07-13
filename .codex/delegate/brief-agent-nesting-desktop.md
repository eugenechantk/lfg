# Delegation Brief: agent-nesting-desktop — parent-child agents in the macOS app

**Goal:** mirror the iOS agent-nesting (commits fb01fa8 + 952aad3 — read both diffs) in
the macOS desktop app: tagged agent sessions (`parentSessionId` on the API row) nest
under their parent's row behind a collapsible "N agents (· M running)" disclosure with
indented child rows; orphans (parent not visible) fold into one collapsed "Agents"
section at the bottom; untagged behavior byte-identical.

**Repo:** worktree of `lfg`, branch worktree-agent-filter. Allowed:
`desktop/LFGSessions.swift` ONLY. It's a single-file SwiftUI macOS app built by
`desktop/build.sh` (no Xcode project). Match its existing style exactly.

## Context (read first)

- `desktop/LFGSessions.swift` — `APISession` (lenient manual Decodable — add
  `parentSessionId: String?` the same way), `SessionItem`, `ListSection`, `sections`,
  the ForEach render loop, `isCollapsed`/`sectionHeader`.
- `git show fb01fa8` + `git show 952aad3` — the iOS behavior being mirrored (grouping
  rules, needs-input equivalent, orphan fallback).
- Desktop's status groups are paused/working/idle/closed: the "never hide a blocked
  agent" exception maps to **paused** — a paused (prompt-waiting) agent stays top-level
  in Paused.

## Spec

1. `APISession.parentSessionId: String?` (lenient decode; absent → nil).
2. Status grouping: children (parent visible in the current filtered list) leave their
   groups; parent rows gain a disclosure line ("N agents", "· M running" if any child
   working) toggling per-parent expansion (@State set); expanded children render
   indented beneath the parent using the same row view (click/open behavior intact).
   Sort children lastActivityAt desc; collapsed by default.
3. Orphans → one collapsed "Agents" section rendered last, same header interaction as
   whatever collapse affordance exists (mirror the iOS pattern with the desktop's
   section header style).
4. Closed sessions and every untagged flow: unchanged.
5. macOS specifics: keep AppKit/SwiftUI idioms already used in the file; no new
   dependencies; the file must keep compiling via `desktop/build.sh`.

## Verification

1. `bash desktop/build.sh` succeeds (run it; report output). If the sandbox blocks
   compilation, say so.
2. State the render tree for: parent with 1 running child collapsed/expanded; orphan;
   paused child.

## Definition of done
- [ ] Tagged rows nest under visible parents; orphan fallback section; paused exception.
- [ ] Untagged rendering unchanged; build.sh green.

**Report back:** files changed, build output, render trees, deviations.
