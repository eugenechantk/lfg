# Shared chat chrome and composer

Product tier. Chats should match the Sessions title bar, input, edge fades and control transitions.

## Success criteria

- Both screens use ConversationToolbar and SessionTitleBarContent.
- Both use MessageComposer in S2 mode, including multiline sizing, model chip styling and animated Send/Stop replacement.
- Both use ConversationHeaderFade and ConversationComposerFade. Their scroll policies remain appropriate to each transcript.
- Empty chats stay centered above the input. Keyboard dismissal retains drafts. Sending clears the field and keeps the latest text visible.
- Offline sends show their saved text and queued/retry state. Model selection, settings and prior Sessions filtering remain available.

## Final architecture

ConversationHeaderFade and ConversationComposerFade share the Sessions edge treatment. ComposerModelLabel shares its model-chip appearance. MessageComposer accepts feature-specific accessibility identifiers and a text-only S2 option. Sessions keeps its attachment action; the current chat transport accepts text.

Chats retains its native safe-area input inset and normal ScrollView. It follows the newest marker through its existing ScrollViewReader when the keyboard changes, using the same explicit follow pattern as Sessions. Only a user scroll changes whether it follows replies, so keyboard resizing cannot silently disable follow. Sessions retains its existing inverted transcript and keyboard policy. The generic full-height surface and experimental clearance calculations have been removed. The shared controls and fades provide visual consistency without coupling these scroll policies.

The chat callback enqueues the submitted text because MessageComposer clears its binding before dispatch. A local persistence failure restores that text when the field is empty. The durable queue, host routing and history storage are unchanged.

Transcript rows still differ. Chats renders ChatMessageRecord text through Markdown and user bubbles. Sessions renders richer SessionMessage rows, tools and files. This turn shares the requested chrome and input.

## Refactor guard and verification

Low-risk extraction of fade placement and model-label presentation; medium-risk integration of the shared input. Existing queue, keyboard and transcript suites characterize the underlying behavior. Native recordings must establish focus/dismissal, multiline growth, send/Stop, latest-message visibility, offline optimistic text and iPad layout.

- LFGCore: 588 tests across 91 suites pass.
- iOS native compile passes at 04:43:12 UTC on 2026-11-04.
- Final Mac native compile passes at 04:51:16 UTC; 287 desktop assertions pass.
- Independent native audit: PASS on owned iPhone 17 Pro and iPad Pro 11-inch simulators, iOS 26.3. Both iPad orientations pass.
- Native recordings verify keyboard focus/dismissal, multiline drafts, newest-reply visibility, immediate offline queued text, input clearing, Send/Stop transitions and historical reading without jumping to the newest response.
- Audit report: `.codex/evidence/chat-shared-surface-audit/evidence.md`.
- Canonical XcodeGen project restored; saved FlowDeck defaults unchanged. Source hashes match the audited build. The isolated fixture and all owned recordings/UI sessions are stopped.

## Audit findings and corrections

Sharing the complete inverted viewport caused low empty-state placement, obscured replies, keyboard overlap and oversized blank end space in the normal chat transcript. The final design preserves each existing scroll layout and shares the visual primitives. Chat now updates follow intent only during a user scroll, so keyboard resizing cannot disable newest-reply following. Historical rows can shift within the viewport during resizing, but the reader is not sent to the newest response. Failed captures remain in the audit folder for comparison. A separate transient native push stalled once; reboot/relaunch restored controls without a code change for that state.

## Scope and residual risks

Preserve prior shared-chrome, keyboard and Sessions-filter changes and all unrelated work. No commit, push or release requested. Verification uses owned iPhone/iPad simulators and isolated fixture hosts. Physical devices, production connectivity and older iOS runtime behavior are outside the native audit.
