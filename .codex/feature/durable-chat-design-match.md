# Match durable chat to the supplied UI map

Implement the linked Chat & Cua Spaces board for the existing durable text-only chat. Keep private instructions, memory, transcript paging, interruption, model changes, idempotent sends, host identity, and read tracking. Exclude Space and desktop features.

Acceptance: the continuous activity-sorted list, monograms, status dots, dark hierarchy, header controls, list dock, thread composer, creation sheet and private details follow the supplied design. iPad keeps the dock in its sidebar. Mac keeps the native host shell. Native platform controls and actual supported capabilities are explicit adaptations.

Evidence and component/state coverage: ../../design/durable-chat-match/component-breakdown.md.

Validation: focused LFGCore presentation/client tests, current simulator build, deterministic fixture flows, independent design verification and iOS visual evidence audit. Do not infer visual correctness from a successful build.
