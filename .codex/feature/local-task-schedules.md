# Local task schedules

Product change for iPhone, iPad, and desktop.

Show the readable schedule in the device timezone in both the list and task detail. In the detail, place it between the title and instructions. Use `SESSIONS` for the history heading so it differs from `Show more`.

## Success criteria

- One-time dates and cron times use the device timezone and clock format.
- Cron conversion shifts weekdays when crossing midnight and uses the next run for daylight-saving offsets.
- If a converted recurrence cannot be described safely, show the exact local next run.
- List and detail show the same schedule. The detail schedule appears above the collapsible instructions.
- The history heading reads `SESSIONS`; individual session titles keep their original text.
- Stored schedules and execution do not change.

## Tests

`ScheduledTaskScheduleDescriptionTests` covers date rollover, weekday rollover in both directions, summer and winter offsets, fractional-hour zones, multiple times, and conservative calendar fallbacks. Native simulator screenshots cover hierarchy and matching list/detail text.

## Verification

All 255 LFGCore tests in 39 suites pass. Both iOS and desktop builds pass.

Independent audit: PASS on iPhone 17 Pro and iPad Pro 11-inch. It confirmed matching local times, the detail hierarchy, the uppercase heading, unchanged session title case, and the instruction toggle. Report: `.codex/evidence/20261010-110239-ios-visual-audit/evidence.md`.

Desktop native snapshots show both recurring and one-time schedules above the instructions. These prove static rendering; the instruction toggle was exercised on iPhone. Evidence: `.codex/evidence/local-task-schedules/audit/desktop/`.

The source matches the audited candidate. The read-only fixture was stopped and the Mac was re-locked. No release, commit, host deployment, or server restart.

## Residual risks

Converted cron labels reflect the offset at the next run. They update when the host supplies a later run across a daylight-saving transition. Unusual cron syntax retains the exact next-run fallback.
