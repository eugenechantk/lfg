# Feature: Task editor pickers

## User story

Edit a scheduled task without typing a model, directory, timezone, or full cron expression.

## User flow and success criteria

- The model dropdown groups Claude and Codex using the same host catalog as Create Session. Selecting a model also selects its agent.
- Keep a saved model, including the agent default, until the user selects another model.
- One directory row shows the path. On iOS and iPadOS it opens the existing Create Session directory sheet, including search and adding a path.
- Directory choices come from the task's host. Selecting a directory does not change the model.
- A searchable timezone list replaces free text. Preserve the selected identifier and absolute one-time instant.
- Five labeled cron fields accept numbers or an asterisk. Use numeric keyboards and an asterisk button. Show valid ranges and disable Save for invalid values.
- Preserve existing cron ranges, steps, and named values when another field changes. The server remains the final schedule validator.
- Save persists the chosen values without changing task identity or run history. Cancel discards edits.
- Keep Edit with chat and the existing desktop task flow.

## Test strategy

Swift tests cover cron bounds, empty fields, saved advanced values, payload round trips, model catalog behavior, and one-time instants.
An independent iPhone and iPad audit records selection, save, reopen, and cancel using isolated task fixtures.
Compile the desktop and verify its native form against the same fixture.

## Refactor guard

Move existing model catalog definitions unchanged into a Foundation-only file so desktop and iOS use one list source. Existing model and effort tests cover the public behavior.

## Tests and results

- `ScheduledTaskEditorTests`: six tests cover bounds, empty fields, saved cron syntax, payload values, absolute dates, and recovery from pasted whitespace.
- Targeted model, scheduler, chat, and creation suites: 28 XCTest and 42 Swift Testing checks passed.
- Desktop feature tests: 173 assertions passed.
- iOS FlowDeck build and desktop compilation passed.
- Native desktop verification passed for model, directory, timezone, asterisk, save, reopen, and cancel. Task identity and history stayed unchanged.
- Evidence: `.codex/evidence/task-editor-pickers/desktop-verification.json`.
- Independent iPhone and iPad audit passed. The final phone regression confirmed pasted whitespace stays in one field; correcting it allows saving and reopening the exact schedule.
- Visual report: `.codex/evidence/20261010-114100-ios-visual-audit/evidence.md`.

## Residual risks

No production tasks changed. Numeric entry through background macOS automation did not commit SwiftUI bindings; simulator typing and repair of invalid values passed the independent audit.
No TestFlight upload, commit, or deployment is included in this change.
