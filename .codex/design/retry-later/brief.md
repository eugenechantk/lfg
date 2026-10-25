# Retry later design brief

Eugene asks: "Delegate a Claude agent to help you do some design for this first and then re-implement with better design using our design language and design patterns."

You are the delegated Claude designer. Design first; the parent Codex agent will implement after reading your outputs. This is a native SwiftUI app for iPhone, iPad, and macOS, not a new web product.

## Ownership and constraints

You own ONLY these output files:
- `.codex/design/retry-later/design.md`
- `.codex/design/retry-later/preview/index.html`

You are not alone in this codebase. Do not edit product code, revert other work, change real tasks, run servers, commit, push, or deploy. Return a concise recommendation in your final answer. Do not create session logs or unrelated artifacts.

Use Read, Glob, and Grep to research existing patterns and screenshots. Write your two outputs. No browser or live app automation is required for this design proposal. Keep output concise and implementable.

## Existing behavior to preserve

- A failed task has Retry now and Retry later.
- Retry later accepts 35, 45, or 60 minute presets, custom whole minutes, or an exact local date/time.
- Show the actual upcoming retry time before confirmation, including local timezone.
- A retry is one extra run; recurring settings and occurrence budgets remain unchanged.
- A pending retry displays its time and can be changed/cancelled.
- Invalid values cannot save. Saving shows progress. Network failure retains input and displays a clear error.
- Host must be awake; a sleeping host retries on return.

## Read these sources

- `.claude/feature/lfg-ios-design-baseline.md`
- `.claude/feature/tasks-a2-redesign.md` (read its initial design/component sections, not the full historical log)
- `shared/Tasks/TaskDetailViews.swift` (TaskPalette, TaskDetailMetrics, TaskStatusCard, TaskRetryLaterSheet)
- `shared/Tasks/TaskEditorViews.swift` and `shared/Tasks/TaskEditorMacViews.swift` (existing schedule forms and chips)
- `shared/Tasks/TaskListViews.swift` (TaskColors)
- `ios/LFG/NewSession/NewSessionSheets.swift` and `NewSessionTheme.swift` (existing sheet patterns)
- `ios/LFGCore/Sources/LFGCore/TaskDetailPresentation.swift`
- Current screenshots:
  - `.codex/evidence/20261018-084454-ios-visual-audit/ipad/02-retry-sheet.png`
  - `.codex/evidence/20261018-084454-ios-visual-audit/iphone/04-relative-7min-saved.png`
  - `.codex/evidence/20261018-084454-ios-visual-audit/mac/06-minutes-sheet.png`

## Deliverables

1. `design.md`: Diagnose why the current generic form feels apart from the task design. Recommend one direction grounded in named existing components/tokens. Specify the failed-card action hierarchy, compact sheet layout, minute chips/selection state/custom entry, exact-time mode, confirmation preview, pending status, loading/error/validation, accessibility, and phone/iPad/Mac adaptation. Give concrete spacing, sizes, colors by existing token, and product copy. Reuse native controls and existing code; no new visual system or ornamental illustration. Avoid expanding scope beyond Retry later.
2. `preview/index.html`: One self-contained HTML design board with CSS-only native-like mockups. Include a phone failed card, phone minutes sheet, exact-time sheet, pending card, and compact Mac sheet. Show dark and light. Use system fonts, actual app colors, believable copy, and selected preset state. Make a reviewer able to compare the intended layout and hierarchy. Label this as a design proposal, not runtime proof. No external assets or dependencies. This board is for inspection, not app code.

Choose a compact focused sheet with clear action hierarchy if consistent with the existing app. Keep all controls reachable with a keyboard on phone and in a narrow Mac window. Do not request user approval; the user already asked the parent to implement after your design pass.
