# Feature: Native iOS App

## User Story

As an lfg user, I want a native Swift iOS client for my existing lfg server so that I can monitor and drive coding-agent sessions from my phone without relying on the installable PWA shell.

## User Flow

1. Open the native app.
2. Enter or confirm the lfg server URL.
3. View live sessions, users, repos, and configured agents from the server.
4. Create a new agent session by choosing repo, owner, agent backend, model, and prompt.
5. Open a session to read streamed transcript updates, send follow-up messages, answer prompts, change model or owner, interrupt, and close.
6. Review auto-agent findings and run/manage insight agents from native screens.

## Success Criteria

- [x] SC1: The GitHub repository is forked and local work is based on the fork. Verify by `git remote -v`.
- [x] SC2: A Swift native iOS app project exists under `ios/` and is generated from a reviewable `project.yml`. Verify by `xcodegen generate`.
- [x] SC3: Shared API/domain logic is covered by deterministic Swift tests. Verify by `swift test` in `ios/LFGCore`.
- [x] SC4: The app can load dashboard data from the existing lfg backend endpoints. Verify by API client tests with a mocked data loader.
- [x] SC5: The app can create, update, and control sessions using the same backend contract as the PWA. Verify by request-building tests and app code paths.
- [x] SC6: The app can consume `/api/live/stream` server-sent events and apply message, busy, prompt, and queue updates. Verify by parser tests.
- [x] SC7: The SwiftUI app builds and launches in Simulator. Verify by FlowDeck build/run.
- [x] SC8: The app shows existing coding-agent transcript messages when a live session is opened, not only messages received after the native app connects. Verify by API client tests and FlowDeck UI against mock and real backend sessions.

## Test Strategy

- Put platform-neutral models, API client, request builders, and SSE parsing in `ios/LFGCore`.
- Use Swift Testing for API decoding, URL construction, request body encoding, and SSE event parsing.
- Use FlowDeck for native app build/run validation because this is UI-impacting iOS work.

## Tests

### Unit

- `ios/LFGCore/Tests/LFGCoreTests/LFGClientTests.swift`
  - `loadsDashboardData` verifies SC4.
  - `buildsCreateSessionRequest` verifies SC5.
  - `loadsSessionMessages` verifies SC8.
  - `surfacesServerErrors` verifies API error handling.
- `ios/LFGCore/Tests/LFGCoreTests/SSEParserTests.swift`
  - `parsesChunkedMessages` verifies SC6.
  - `ignoresHeartbeats` verifies SC6 heartbeat handling.
  - `decodesLiveEvents` verifies SC6 event decoding.

## Implementation Details

- Keep `src/` and `web/` intact; the native app is an additional first-class client for the existing `lfg serve` API.
- Use XcodeGen for a generated Xcode project so project structure remains readable and reproducible.
- Persist server URL and user preferences with `UserDefaults`/`@AppStorage`.
- The iOS app covers the primary PWA control-plane flows: settings, sessions list, new session, live message stream consumption, prompt answer/dismiss, send/retry, assign/model/interrupt/close, auto findings, auto agents, insight agents, and reports.
- The iOS app backfills session transcript messages from `/api/sessions/:id/messages` and then tails `/api/live/stream`, matching the PWA's backlog-plus-live behavior.
- After native composer sends, the app runs a short delayed transcript backfill loop so assistant replies still appear if the live SSE tail misses the exact transcript append event.
- Terminal emulation, browser extension tabs, image upload, and voice recording are not fully native in this first pass.

## Residual Risks

- Full terminal emulation is not ported. The existing PWA terminal uses `ghostty-web`; a native equivalent should be a separate pass with a terminal parser/view.
- Voice dictation/STT is not ported. Native speech recording should be implemented with AVFoundation/Speech or the existing TTS/STT proxy in a separate pass.
- Independent visual auditor was not run because the available sub-agent tool explicitly forbids spawning sub-agents unless the user asks for delegated agent work. Direct FlowDeck screenshots were captured instead.

## Verification Evidence

- `gh repo fork BennyKok/lfg --clone --remote=true --default-branch-only` created `https://github.com/eugenechantk/lfg`.
- `git remote -v` shows `origin` as `https://github.com/eugenechantk/lfg.git` and `upstream` as `https://github.com/BennyKok/lfg.git`.
- `xcodegen generate` completed and created `ios/LFG.xcodeproj`.
- `swift test` in `ios/LFGCore` passed 7 Swift Testing tests.
- `flowdeck build` passed for scheme `LFG` on simulator `AA8AA864-E30F-4483-A83F-5340A473719F`.
- `flowdeck run --json` built, installed, and launched bundle `dev.omg.lfg`.
- Direct FlowDeck UI validation covered Sessions offline, Settings, New Session with live repo data, Auto, Agents, and Agent Detail screens.
- Real-agent E2E spawned an `aisdk`/`haiku` session, verified native transcript display, sent follow-up messages from the app, and confirmed the second assistant follow-up appeared in the native detail transcript without manual refresh.

## Bugs

_None yet._
