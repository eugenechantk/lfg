# Delegation Brief: agent-nesting — child agent sessions group under their parent's row

**Goal:** evolve the just-landed Agents feature (commit fb01fa8): instead of one flat
collapsed "Agents" section, a tagged agent session renders NESTED under its PARENT
session's list row — the parent row gains an "N agents" disclosure; expanding it shows
indented child rows directly beneath. The bottom "Agents" section remains ONLY as the
fallback bucket for orphans (parent sessionId not present in the current list).

**Repo:** worktree of `lfg`, branch worktree-agent-filter (fb01fa8 is HEAD — read its
diff first: `git show fb01fa8`). Allowed: `ios/LFG/SessionListView.swift`,
`ios/LFG/Components.swift` (only if the row card needs a shared sub-view),
`ios/LFG/SessionStore.swift` (minimal, only if grouping helpers belong there). No server
changes (the tag already flows). Swift 6 strict.

## Spec

1. **Grouping (Status mode):**
   - Children = sessions whose `parentSessionId` matches a session PRESENT in the
     current filtered list; they leave their normal group.
   - Parent rows render where they always did. A parent WITH children shows, inside/
     beneath its existing row card, a compact disclosure line: chevron + "N agents"
     (+ "· M running" when any child is busy — reuse the store's group/busy helpers).
   - Tapping the disclosure toggles per-parent expansion (@State set keyed by parent
     sessionId, like expandedDirs). Expanded → child rows render immediately beneath the
     parent, visually indented (leading padding ~24pt), using the SAME row component so
     navigation/swipe actions keep working.
   - Child order: lastActivityAt desc. Collapsed by default.
2. **Exceptions (keep from fb01fa8):** a child in `.needsInput` surfaces in "Needs you"
   normally (never hidden behind a collapsed parent). Orphan agents (no visible parent)
   fold into the existing bottom "Agents" section unchanged.
3. **Directory mode + search:** unchanged. (In search, children match on their own and
   may render top-level in results — acceptable and simplest.)
4. Untagged lists render byte-identical to fb01fa8.

## Verification

1. `cd ios/LFGCore && swift test` green (no LFGCore changes expected — confirm).
2. Build via flowdeck if sandbox permits; else say so.
3. State the render tree for: parent with 2 children (1 busy) collapsed vs expanded;
   an orphan agent; a child in needsInput.

## Definition of done
- [ ] Children nest under visible parents with disclosure + indent; per-parent expansion.
- [ ] Orphans → bottom Agents section; needs-input exception preserved.
- [ ] Untagged behavior unchanged; suites green.

**Report back:** files changed, the render trees, build/test output, deviations.
