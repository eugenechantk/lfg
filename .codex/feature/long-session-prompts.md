# Long session prompts

## User story

Scheduled tasks must start with their complete saved instructions, even when the prompt exceeds tmux's command limit.

## User flow

The host loads the saved task and creates its session. Large launch commands use a private local file. The launcher passes the original text to the agent as one argument, then removes the file. Short commands keep their current path.

## Success criteria

- [x] SC1: Long Claude and Codex launches preserve every argument, including Unicode, quotes, newlines, shell syntax, and trailing semicolons. Verify with real tmux and an argument recorder.
- [x] SC2: Temporary launch files are private, unique, removed after consumption, and removed on launch failure. Verify file permissions and failure tests.
- [x] SC3: Existing short launches, resume, fork, and Codex pane styling still work. Verify existing argv tests and targeted session tests.
- [x] SC4: The production host accepts a harmless long prompt and its session receives the complete text. Verify through the live session API and transcript.
- [x] SC5: Existing phone schedules and run history remain intact. Verify the task API before and after activation.

## Platform

Bun backend and tmux. No client UI change.

## Decision log

- The task store already preserves the full prompt. The failed run had 18,469 characters and returned `command too long` before creating a session.
- Fix the shared launch transport for both providers, including task setup and ordinary sessions.
- Use a private shell launcher with every argument single-quoted as literal data. Launch the real CLI with `exec` so terminal and process ownership stay intact. Do not paste into a cold TUI or ask the model to fetch a brief.
- Preserve schedule times and failed-run history. Do not silently retry phone work outside its allowed start window.

## Verification evidence

- `bun test` across nine focused launch, scheduler, create, fork, and managed-session suites: 64 passed, zero failed. Evidence: `.codex/evidence/long-session-prompts/targeted-tests.log`.
- Real tmux tests preserved complete arguments and TTY ownership, including Unicode, literal shell syntax, trailing semicolons and trailing newlines. Private directories used mode 0700 and scripts 0600. Successful and failed launches removed their files.
- `bun build src/cli.ts --target bun`: 588 modules bundled. `git diff --check`: clean.
- One broader binary-resolution fixture failed because the installed Codex version outranked its dated mock binary. The unchanged HEAD version failed identically. Evidence: `baseline-tests.log`. This pre-existing fixture issue is outside the launch transport change.
- Production host activated at 2026-10-15 01:07:45 HKT. Listener PID changed from 16633 to 89039. All 20 existing agent processes survived; all 18 known session IDs returned.
- Live `/api/sessions/new` accepted 25,315 characters (27,315 UTF-8 bytes). The returned user transcript matched the original exactly; the agent replied `LFG_LONG_PROMPT_OK_20261015`. The probe session was closed after verification. Evidence: `live-proof.json`, `live-messages.json`, `live-close.json`.
- Task API snapshots before and after activation were exactly equal. No schedule, prompt, run history, or phone action changed.
- Independent audit: PASS. The auditor ran 29 tests and 12 isolated real-tmux probes, including 117,605-byte prompts for both providers across fresh, resume, and fork. It independently checked live transcript equality and unchanged task snapshots. Evidence: `audit/report.md`. The specialized auditor model was unavailable, so a separate default agent performed the independent audit.

## Bugs

Fixed: long prompts no longer cross tmux IPC inline.

Known unrelated test issue: the binary-resolution fixture assumes all installed Codex versions are older than 0.153.4. It fails on unchanged HEAD too.

## Limits

This removes the tmux message limit. Operating-system argument limits still apply. The scheduled-task API retains its existing 50,000-character limit. No commit or push occurred.
