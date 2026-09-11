# Sign in on phone

Product tier. Branch `feature/phone-sign-in`, based on streaming commit `9b311fb`.

## User story and flow
Open Sign in on Phone from a session. The exact owning host lists connected browser destinations. Choose the Chrome profile running Claude or a named Playwright context, enter an HTTPS site, and log in in an isolated WKWebView. Review cookie domains and explicitly send to the chosen destination. Show adapter-confirmed delivery, then let the user return to the agent and continue. No automatic agent messages, pause, resume, or login-success inference.

## Success criteria
- [x] SC1: More menu opens URL/destination form; login webview and domain review are usable on iPhone/iPad — builds and recorded simulator flow.
- [x] SC2: Only selected domains' cookies go to the selected browser on the owning host — Swift serialization/filtering tests and real HTTP/WebSocket integration.
- [x] SC3: Companion extension imports HttpOnly/Secure/session cookies into its own normal Chrome profile with explicit per-site permissions — real Chromium extension fixture; personal Chrome installation is a user setup step.
- [x] SC4: Playwright bridge imports into an existing context without replacing/closing it — real Chromium protected-page fixture.
- [x] SC5: Invalid, oversized, cross-origin, expired, unauthenticated adapter traffic and wrong-target acknowledgments fail closed; no secret journals/files — boundary/integration tests and code review.
- [x] SC6: Offline destination, failed/partial import, timeout and cancel have honest outcomes; ephemeral phone data discarded on dismissal — tests and simulator recording.

## Design decisions
- Separate native phone login and transport from two interchangeable browser adapters. No video dependency.
- Browser adapters connect only to loopback LFG using a random local setup token (0600 file created explicitly by setup script); no token in URL or logs. Chrome stores its setup token locally, has no content scripts and requests website permissions on its options page.
- Live WebSocket targets; no queued credentials for offline browsers, no automatic replay. One bounded import per target. Payload lives in memory only, expires on timeout, and acknowledgments return counts/status rather than cookie contents.
- HTTPS login sites only. Preserve cookie attributes, allow explicit domain selection, no cross-site storage scraping or Google UA spoofing. Only cookies in v1; Google embedded OAuth, localStorage-only and device-bound sessions may require Browser Stream.
- Delivery means cookies installed, not authentication proven. User refreshes the destination page explicitly; never reload a working tab automatically.
- Existing Cloudflare-gated iOS transport reused; enforce HTTPS off-loopback for credential transfer. Development fixtures are loopback-only. No production listener restart or database operations.

## Verification evidence
- Streaming checkpoint: committed `9b311fb` on `feature/browser-stream`; new work is on child branch `feature/phone-sign-in` in the same isolated worktree. Main working tree untouched, no pushes.
- FlowDeck iOS build/run PASS on iPhone 17 Pro (latest app run `8604A879`, September 12 Hong Kong). Initial compile error (optional host name) fixed; Foundation SameSite extraction now uses the public typed API.
- `swift test --package-path ios/LFGCore`: 463 XCTest + 117 Swift Testing tests PASS. Four new tests cover HTTPS/URL policy, exact selected-domain filtering, Foundation cookie attribute extraction, and owning-host request credentials/cache policy.
- Bun stream/preview/sign-in suites: 22 tests / 92 assertions PASS, including forged acknowledgments from another authenticated browser, target invalidation after timeout, partial import, proxy HTTPS, secret-free errors and body limits.
- Real Chromium tests: HTTP POST -> authenticated WebSocket -> existing Playwright context changes protected fixture response 401 to 200, leaves another context empty, preserves HttpOnly/Secure/session attributes. Real MV3 extension setup is driven through its Options form (token clears after Save), then imports into an isolated profile and refuses an ungranted domain. Test-only manifest pregrants the synthetic domain; real Chrome consent remains a setup step.
- Token setup smoke test: PASS in a disposable directory; mode 0600, 64-character random token, repeat invocation preserves existing token, values suppressed.
- `bunx tsc --noEmit --pretty false`: PASS, including central server registration. Standalone setup/CDP/UI-fixture scripts separately typechecked PASS.
- Independent audit PASS for exercised iPhone/iPad scope: both full native WKWebView login -> review -> delivery flows; destination fixture changed from installed:false to true. Domain deselection disables Send; Cancel/reopen and Start another sign-in clear cookies; invalid HTTP, Google unsupported, disconnected-target result and no-browser states are correct. No blocking product defect found. Full recordings and screenshots are in the audit report.
- Initial UI fixture immediately closed SSE, causing excessive app reconnection/CPU and slow AX automation. Fixed fixture to retain the stream and stable session timestamps; relaunched app CPU dropped from 113% to 5.6%. Initial incomplete recording is not acceptance evidence.

### Evidence paths
`.codex/evidence/phone-sign-in/` and independent `.codex/evidence/phone-sign-in/audit/`.
Final test logs are saved there. No actual passwords, account cookies or production browser profiles were used.

## Implementation files
- `ios/LFG/PhoneSignInView.swift`: isolated WKWebView, HTTPS navigation, target selection, explicit domain review, delivery/recovery UI, privacy overlay and cleanup.
- `ios/LFGCore/Sources/LFGCore/PhoneSignIn.swift`, `LFGClient.swift`: cookie model/filtering, owning-host authenticated request and redirect rejection with ephemeral URLSession.
- `src/browser-sign-in.ts`, `src/commands/serve.ts`: target registry, authenticated local adapters, bounded credential transport, acknowledgments, deadline/disconnect handling.
- `extensions/phone-sign-in/`: MV3 companion extension with domain permissions/options, connection state and Chrome cookie installation. README contains setup instructions.
- `src/browser-sign-in-playwright.ts`, `scripts/browser-sign-in-playwright.ts`: attach to an existing context, or connect to an explicitly supplied local CDP endpoint.
- `scripts/browser-sign-in-setup.ts`, `scripts/browser-sign-in-fixture.ts`: explicit token provisioning and disposable native-UI acceptance fixture.
- Bun/Swift tests, dependency lockfile and generated iOS project accompany the implementation.


## Residual risks
Real password AutoFill/Face ID and third-party portal compatibility require user testing. No real account credentials used in automated tests. Browser extension must be loaded in the user's chosen Chrome profile before it appears on the phone.

## Completion and setup

Independent report: `.codex/evidence/phone-sign-in/audit/report.md` (PASS for exercised UI scope). Full phone and iPad recordings finalized and decoded samples inspected by the auditor. Supplemental cancel/offline recording also finalized and decoded successfully (three verified recordings total).

Scratch fixture on 9982 stopped after audit; no production listener/restart, personal Chrome extension installation, database operation, push or deployment performed. Sign-in implementation remains uncommitted for review on `feature/phone-sign-in`; streaming checkpoint remains committed at `9b311fb`. See `extensions/phone-sign-in/README.md` for the concrete Chrome/Playwright setup. Real portal compatibility and physical-device AutoFill/Face ID remain explicit acceptance work for the user's accounts.

## Final acceptance and commit scope
- Real App Store Connect acceptance passed on Hihi: user signed in on iPhone and sent the login; the personal Chrome companion received it and the protected `/apps` page showed the authenticated account and full app list. No desktop credentials were entered. Live setup evidence is in the main checkout at `.codex/feature/phone-sign-in-live-setup.md`.
- Added an optional **Allow all websites** button; user enabled all HTTPS sites. Phone-side cookie-domain review/filtering still applies.
- Per user request, removed Browser Stream entry points from the More menu and composer, and removed help that directs users to the hidden feature. Streaming implementation remains in the repository and earlier streaming checkpoint.
- Commit only this isolated feature worktree; preserve unrelated dirty work in main. Never include ignored private Cloudflare bootstrap, pairing token, build products, or account screenshots in the commit.
- Final verification: 8 Bun tests / 51 assertions, 4 focused Swift sign-in tests, TypeScript check, and simulator/device builds passed. Installed and launched on Hihi (FlowDeck run `49EBC9A6`). Independent iPhone and iPad entry-point audit PASS: no Browser Stream in composer/More, Sign in on Phone opens and lists live Chrome. Eight screenshots and report: `.codex/evidence/hide-browser-stream/report.md`.
