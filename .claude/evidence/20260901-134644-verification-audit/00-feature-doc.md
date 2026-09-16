# Feature: Desktop Create Session

## User Story

As an LFG desktop user, I want a create-session button in the top toolbar so I can jump from a session search directly into a new iTerm session for that project.

## User Flow

1. Search for a project, directory, or remembered session text in the desktop session list.
2. Press the top-toolbar create button.
3. LFG resolves the strongest matching directory, finds the newest session in that exact directory, and reuses its valid agent/model pair.
4. LFG creates the session on the host associated with the directory match and opens its tmux session in iTerm.
5. With an empty search, LFG uses the default reachable host's Inbox and the same default agent/model pair as iOS.

## Success Criteria

- [ ] SC1: A top-toolbar Create Session button is visible in full and compact desktop layouts. — **Verify by:** desktop window snapshots plus Accessibility tree inspection.
- [ ] SC2: A non-empty search selects the strongest matching directory and uses the newest valid agent/model pair from that exact directory. — **Verify by:** `--desktop-feature-test` planner cases.
- [ ] SC3: Empty search creates in the default host's Inbox with iOS's default Claude model. — **Verify by:** `--desktop-feature-test` planner case plus create-flow HTTP integration probe.
- [ ] SC4: Successful creation opens the returned tmux session in iTerm using the existing local/remote opener behavior; failures surface in the existing alert. — **Verify by:** `--desktop-feature-test` response/item mapping and opener command cases, plus macOS runtime audit where environment permissions allow.
- [ ] SC5: Existing desktop behavior and current in-progress pagination/filtering edits remain intact. — **Verify by:** clean desktop build and complete `--desktop-feature-test` pass.

## Test Strategy

- Pure planner tests cover empty-query fallback, directory relevance, exact-directory model history, missing/retired model fallback, and no-match behavior.
- Existing headless desktop feature tests cover opener command construction and regressions.
- Off-screen window snapshots cover toolbar presence at representative full/compact widths.
- Cursor-free macOS Accessibility automation verifies the real built app when TCC and an unlocked login session are available.

## Implementation Details

- Keep decision logic outside SwiftUI `body` in a pure planner.
- Extend resumable desktop rows to retain best-effort model metadata already emitted by current hosts.
- Use `GET /api/dirs` for Inbox resolution and `POST /api/sessions/new` for creation.
- Reuse `Opener.open` for the returned tmux session so local and remote attachment behavior cannot drift.

## Decision Log

- An exact directory path/basename match outranks a newer session that merely mentions the search term; otherwise the newest matching session supplies the directory.
- The selected match's host owns creation. This avoids sending a host-specific path to an unrelated default machine.
- Model history is scoped to that same host as well as the exact normalized path, so identical paths on two Macs cannot leak defaults across machines.
- A non-empty query with no directory-bearing match reports an error instead of silently creating in Inbox.
- Empty-query behavior uses the first configured reachable host, matching iOS's reachability-aware default-host intent.

## Verification Evidence

| Criterion | Verification | Result / artifact |
|---|---|---|
| SC1 | Deterministic SwiftUI window snapshots at 440pt compact and 900pt full width | PASS — `.codex/evidence/desktop-create-session/compact-440-final.png`, `.codex/evidence/desktop-create-session/full-900-final.png`; Create (`+`) is visible in both. |
| SC2 | `desktop/build/lfg.app/Contents/MacOS/lfg --desktop-feature-test` | PASS — 128 assertions, including exact-directory ranking, selected-host scoping, trailing-slash normalization, newest readable model, agent-default fallback, and no-match behavior. |
| SC3 | Same headless feature suite | PASS — empty query resolves default host + Inbox + `claude` / `claude-opus-5`; request-body assertion covers the create payload shape. |
| SC4 | Same headless feature suite plus existing opener command cases | PASS — request targets `POST /api/sessions/new`; response retains tmux/session/host transport metadata; existing local/remote opener command assertions remain green. No real session was created during verification. |
| SC5 | `desktop/build.sh`; feature suite; `--window-fit 440 568 900`; `git diff --check` | PASS — build succeeds, 128 assertions pass, all compact/full toolbar actions fit, and the whitespace check is clean. Existing dirty-tree work was preserved. |

Independent audit: pending.

## Residual Risks

- The currently running `/Applications/lfg.app` is an older user bundle with the same bundle identifier. It was deliberately not stopped or replaced, so runtime verification used the new build's deterministic snapshot harness rather than mutating the live installation.
- Verification did not press Create against a production host because that would create a real session and open an iTerm window; request formation, response mapping, and opener routing are covered headlessly.

## Bugs

_None yet._
