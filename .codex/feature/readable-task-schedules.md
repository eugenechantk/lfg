# Readable task schedules

Product change for the shared iPhone, iPad, and desktop task list.

## User story

Read when a task runs without interpreting cron syntax or opening its details.

## Success criteria

- [x] Common recurring schedules use plain language, including daily, weekday, weekly, monthly, and interval schedules.
- [x] One-time tasks show their exact date, year, and time, including after completion.
- [x] Times use the device timezone and the user's clock format. The stored task timezone still controls execution.
- [x] Unusual cron syntax has an honest custom-schedule fallback with the next exact run when available.
- [x] The schedule has its own readable line. Host and model remain visible below it.
- [x] Phone, narrow iPad sidebar, and desktop rendering preserve the existing list style.

## Implementation

Keep schedule descriptions in the shared Foundation model. This only changes presentation; scheduling and stored expressions remain untouched.
Use native date formatting. Translate supported cron fields conservatively rather than guessing about special operators.

## Verification

All 251 tests in 39 LFGCore suites pass. The new schedule suite covers recurrence descriptions, timezone conversion, clock formats, completed one-time tasks, malformed input, and fallback behavior. Both iOS and desktop builds pass.
Independent audit: PASS on iPhone and a 320-point iPad sidebar. The auditor also reviewed a desktop snapshot at 760 points. Read-only fixtures verified the actual shared task list without running live tasks. Evidence: `.codex/evidence/readable-task-schedules/audit/evidence.md`.

## Residual risks

Advanced cron operators retain a custom-schedule description with the next exact run when available. Desktop row rendering passed an off-screen snapshot; full desktop window interaction was not verified because native launch/capture was unreliable. The snapshot does not prove toolbar materials.

The original formatter shipped in TestFlight 1.3.0 (202610100934). The follow-up `.codex/feature/local-task-schedules.md` changes presentation to device time and adds the schedule to the detail view. That follow-up has not been released.
