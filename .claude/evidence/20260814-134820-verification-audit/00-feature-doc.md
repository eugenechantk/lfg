# Feature: Desktop Resume Correctness

## User Story

As an lfg desktop user, I want Resume to appear only for stopped sessions and to work for Codex as well as Claude so that opening a session never proposes an invalid or misleading action.

## User Flow

1. View live and closed sessions in the desktop app.
2. A live session with a tmux pane opens by attaching; a live session without an attachable pane does not claim it can resume.
3. A closed Claude or Codex session shows Resume.
4. Opening the closed session starts the matching CLI resume command in a local tmux session.

## Success Criteria

- [x] SC1: A running session without a tmux target does not show or execute Resume. — **Verify by:** `--desktop-feature-test` assertions for `opensByResume`, `canOpen`, and open routing.
- [x] SC2: Resumable API rows retain their Claude/Codex agent identity. — **Verify by:** `--desktop-feature-test` decoding and closed-row conversion assertions.
- [x] SC3: Closed Codex sessions resume with `codex resume <id>` while Claude sessions keep `claude --resume <id>`. — **Verify by:** `--desktop-feature-test` command-generation assertions.
- [x] SC4: The desktop app still builds and its complete headless feature suite passes. — **Verify by:** `desktop/build.sh` followed by `build/lfg.app/Contents/MacOS/lfg --desktop-feature-test`.

## Platform & Stack

- **Platform:** macOS
- **Language:** Swift
- **Key frameworks:** SwiftUI, AppKit

## Steps to Verify

1. Build with `cd desktop && ./build.sh`.
2. Run `desktop/build/lfg.app/Contents/MacOS/lfg --desktop-feature-test`.
3. Confirm the new live/no-tmux, agent-decoding, and CLI-command assertions pass.
4. Run the independent verification audit against these criteria.

## Implementation Phases

### Phase 1: Pin resume classification and agent parity

- Scope: Add headless regression assertions for live/closed classification, resumable agent preservation, and Claude/Codex command selection.
- Success criteria covered: SC1, SC2, SC3
- Verification gate: New assertions fail against the current behavior.

### Phase 2: Correct desktop routing and command generation

- Scope: Preserve resumable agent metadata, require `closed` for implicit Resume, and add the Codex CLI branch.
- Success criteria covered: SC1, SC2, SC3, SC4
- Verification gate: Build and full desktop feature suite pass.

## Decision Log

- A live session without a tmux target is treated as non-openable. Starting a second process with Resume would duplicate a session that the server already reports as live.
- Resume remains a local iTerm/tmux action in the desktop app; only the agent-specific CLI invocation changes.
- Missing `agent` on older resumable API responses defaults to Claude for backward compatibility.

## Verification Evidence

| Criterion | Command / action | Observed result | Artifact |
| --- | --- | --- | --- |
| SC1 | `desktop/build/lfg.app/Contents/MacOS/lfg --desktop-feature-test` | Live Codex without tmux asserted `opensByResume == false`, `canOpen == false`, and `Opener.open` returned the non-attachable-live error before launching anything. Full suite: `{"ok":true,"tests":82}`. | Embedded assertions in `desktop/LFGSessions.swift` |
| SC2 | Same desktop feature suite | Codex resumable JSON retained `agent == "codex"`; a response without `agent` decoded as Claude. Full suite passed. | Embedded assertions in `desktop/LFGSessions.swift` |
| SC3 | Same desktop feature suite | Generated Codex command ended in `resume 'codex-closed'`; generated Claude command ended in `--resume 'claude-closed'`. Full suite passed. | Embedded assertions in `desktop/LFGSessions.swift` |
| SC4 | `cd desktop && ./build.sh && build/lfg.app/Contents/MacOS/lfg --desktop-feature-test` | Build succeeded and all 82 assertions passed. | `desktop/build/lfg.app` |
| Regression | `bun test src/sessions-resumable.test.ts src/sessions-resumable-closed.test.ts src/tmux-argv.test.ts` | 16 passed, 0 failed; confirms the server still lists Codex rows and generates native Codex resume argv. | Test output from 2026-08-14 |
| Hygiene | `git diff --check -- desktop/LFGSessions.swift desktop/README.md .claude/feature/desktop-resume-correctness.md` | Passed with no output. | Working tree |

## Bugs

_None yet._
