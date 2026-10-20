# Unified creation and task instructions

## Scope
Product change for iPhone, iPad, and Mac. Preserve existing unrelated working-tree edits.

## Success criteria
- Task instructions start at three lines with tail ellipsis on every platform and task status.
- Long instructions offer Show more and Show less. Short instructions need no toggle.
- Both plus buttons open the same creation surface within each platform.
- A native segmented control selects New session or New task and defaults to the originating list.
- Switching modes retains prompt, directory, host, and model. Sending uses the selected mode's endpoint.
- Dismissal and reopening restore the current list's default.
- Task authoring continues in a normal session with scheduling tools.

## Validation
Existing request-routing tests, iOS and desktop builds, simulator interaction recording, independent visual audit, desktop AX verification.

## Status
Complete. Independent iOS audit PASS; desktop runtime checks PASS.

## Implementation
- iOS retains one NewSessionView draft while a native segmented picker changes the creation purpose.
- Desktop Sessions and Tasks plus buttons present one shared composer from ContentView's common root.
- Desktop search context seeds the directory, host, agent, and model; an empty context uses configured Inbox.
- Both modes preserve the current draft and choices. Task mode calls scheduled-task authoring; session mode calls ordinary creation.
- Task instructions use one three-line disclosure component for every task status on both platforms.
- Overflow measurement uses the same font as visible text.

## Verification
- iOS final FlowDeck build: PASS (2026-10-20 04:17:31 UTC).
- TaskSessionCreationTests: 6 passed, including conversation/task/conversation switching with retained options.
- Final desktop build: PASS.
- Desktop feature suite: 259 checks passed.
- Desktop runtime: both plus defaults, switching, retained prompt/directory/model, cancel/reopen defaults passed.
- Desktop submission: both selected endpoints and payloads captured against a rejecting local fixture. No session created.
- Desktop failed-task instructions: 3 lines with ellipsis; Show more reveals final sentence; Show less returns to identical 57.25-point text height.
- Desktop evidence: `.codex/evidence/unified-creation/`.
- Independent iOS final audit: PASS. See `.codex/evidence/20261020-121559-ios-visual-audit/evidence.md`.
- iOS audit verified failed and ordinary three-line instructions, complete expansion/collapse, no toggle for short text, both origin defaults/resets, retained draft/directory/host/model, and both submit endpoints.
- Desktop short-text check also passed: full short prompt visible, no toggle.

## Residual risks
No production sessions were spawned and no schedules were changed. This is a local implementation, not a release or installation on Eugene's physical devices.

## Mobile header follow-up
The segmented control replaces the title in the same header row as Close. This removes the separate picker row. Keep both labels, centered alignment, and origin defaults. Verify final layout and switching on iPhone with a recording. Desktop is unchanged.

Status: PASS. FlowDeck build passed. Independent iPhone audit confirmed one header row, no separate title, retained draft across both modes, Close dismissal, and clean New session default on reopen. Evidence: `.codex/evidence/20261020-123525-ios-compact-header-audit/evidence.md`.
