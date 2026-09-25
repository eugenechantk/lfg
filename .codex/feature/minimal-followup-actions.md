# Feature: Minimal follow-up actions

## User Story

As a reader, I can use a suggested next step from an assistant reply without seeing its directive syntax.

## User Flow

An assistant reply containing standalone `:codex-followup[Title]{prompt="..."}` lines shows its ordinary prose, followed by plain text action lines. Tapping a line adds its prompt to the composer and focuses it for review. Existing draft text stays intact.

## Success Criteria

1. Valid follow-up directives render only their titles as minimal text buttons, in source order, with no heading, card, icon, or raw syntax.
2. A tap fills an empty composer or appends to a nonempty draft, then focuses the composer. It never sends automatically.
3. Other markdown and malformed or fenced directives remain readable as prose.
4. User messages remain unchanged.

## Test Strategy

Swift Testing covers directive extraction, malformed/fenced preservation, and draft composition. Simulator proof covers appearance and tapping through a network-free fixture.

## Tests

- `LFGCoreTests/FollowupDirectivesTests`: source order and mixed bullets (SC1), JSON prompt escapes (SC1), malformed/fenced prose (SC3), unchanged user text (SC4), draft preservation (SC2). Five tests passed via FlowDeck on the isolated simulator.
- Existing `LFGCoreTests/TranscriptRowTextTests`: five tests passed, covering image removal, links, plain text, and empty text in the shared derivation path.
- Simulator fixture `LFG_SEND_FOLLOW_FIXTURE=1 LFG_FOLLOWUP_FIXTURE=1`: three plain text actions appeared without raw syntax. A tap filled the composer; a second tap appended while keeping the first prompt. Recordings are under `.codex/evidence/20260925-followup-actions/`.
- Independent visual audit: **PASS**. See `.codex/evidence/20260925-221629-ios-visual-audit/evidence.md` for screenshots, accessibility trees, and full interaction recordings.

## Implementation Details

`FollowupDirectives` extracts complete standalone directives before media scanning. `TranscriptRowText` caches the resulting prose and actions. The transcript row renders 44-point text-only buttons; `SessionDetailView` owns the draft and focus request. The send path is unchanged.

## Residual Risks

The isolated fixture verifies the native rendering and draft behavior; it does not prove every provider's exact escaping format. Malformed directives remain visible to avoid silent loss.

## Bugs

None yet.
