# Feature: iOS Tool Message Disclosures

## User Story

As an lfg iOS user, I want tool calls and tool results to be visually separated from normal user/assistant chat so transcript scanning is not polluted by raw tool payloads.

## User Flow

Open a session transcript that contains adjacent `tool_use` and `tool_result` messages. The transcript shows normal prose as chat bubbles, while tool activity appears as collapsed disclosure rows that can be expanded on demand.

## Success Criteria

1. Tool calls and tool results do not render as user chat bubbles.
2. Adjacent `tool_use` and `tool_result` messages are grouped into one collapsed tool block by default.
3. Each tool call/result inside the group is also a collapsed row by default.
4. The group summary matches the PWA behavior: counts tool calls by tool name and counts results.
5. Expanding reveals the raw message text for inspection.

## Test Strategy

No app-target Swift test bundle exists in this project. This is SwiftUI rendering behavior in the app target, so verification is build plus simulator inspection. Existing package tests do not cover this view.

## Tests

- `build_sim` through XcodeBuildMCP — passed, including final post-cleanup rebuild.
- `swift test --scratch-path /tmp/lfg-LFGCore-swiftpm-build` in `ios/LFGCore` — passed, 7 Swift Testing tests.
- `build_run_sim` through XcodeBuildMCP — passed on iPhone 17 simulator `AA8AA864-E30F-4483-A83F-5340A473719F`, including final post-cleanup relaunch.
- Simulator validation with session `76321efe-6742-4bd3-817b-72f8a4f23096` — passed:
  - adjacent tool messages render as collapsed groups
  - group summary shows `1 Bash · 2 Read · 3 results`
  - nested tool rows show `Bash`, `Read`, and `result`
  - raw tool text appears only after expanding a nested row
  - final screenshot: `/var/folders/cd/_rd32xx17dv8ltmf4ctm5wn40000gn/T/screenshot_optimized_a17b81da-e2f3-4e6b-9bab-4baf25e7ca3c.jpg`

## Implementation Details

Mirror the PWA transcript renderer:
- coalesce adjacent tool messages before rendering
- render tool groups through collapsed `DisclosureGroup`
- render each tool row through a nested collapsed `DisclosureGroup`

## Residual Risks

No app-target Swift tests exist for this SwiftUI rendering code. Simulator validation covered the changed behavior on one real transcript with both tool calls and results.

## Bugs

None yet.
