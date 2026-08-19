# Feature: Bundled Cloudflare Access

## User Story

As LFG's sole private user, Eugene wants iPhone and iPad builds to contain the
Cloudflare Access configuration so a fresh install connects without manually
copying a service-token ID and secret.

## User Flow

1. A local generator reads the existing pilot token from macOS Keychain.
2. It writes a gitignored JSON resource that Xcode bundles into this private
   build.
3. On first launch, LFG validates the resource, writes the credential into its
   device-only Keychain, and adds the protected host when it is not configured.
4. Later builds refresh the Keychain value, allowing token rotation without
   manual device entry.
5. Builds without the private resource retain the existing manual setup flow.
6. If manual setup is shown, the private production hostname is already filled
   in; an existing saved host list is never replaced.

## Success Criteria

- [x] SC1: A valid bundled configuration decodes only when its host is HTTPS
  and all credential fields are non-empty.
- [x] SC2: A private build automatically installs the bundled credential into
  LFG's Keychain and adds the bundled host on a clean install.
- [x] SC3: Existing hosts are not duplicated, and builds without the resource
  behave exactly as before.
- [x] SC4: The real credential is absent from tracked files and generated output
  is explicitly gitignored.
- [x] SC5: The resulting private Simulator build reaches the protected host
  without any credential entry.
- [x] SC6: First-run manual setup pre-fills
  `https://lfg-pro.eugenechantk.me` while preserving saved hosts.

## Test Strategy

- LFGCore unit tests cover configuration decoding, validation, and bootstrap
  host-list behavior.
- Source and Git checks prove the generated resource is ignored and the token
  is absent from tracked files.
- A clean Simulator install proves automatic connection at runtime.

## Tests

- `ios/LFGCore/Tests/LFGCoreTests/BundledCloudflareAccessTests.swift`
  - valid private resource decoding
  - rejection of missing fields and non-HTTPS hosts
  - automatic host insertion without duplication

## Implementation Details

- Keep the private token in macOS Keychain as the source of truth.
- Generate `ios/PrivateResources/BundledCloudflareAccess.private.json`; never
  commit it.
- Decode and validate through LFGCore, then seed the app Keychain before
  `AppSettings` finishes initialization.

## Verification Evidence

- 2026-08-19: The full LFGCore suite passed 361 XCTest cases plus 88 Swift
  Testing cases, including the four bundled-configuration tests.
- 2026-08-19: The generated resource is mode `0600`, is matched by `.gitignore`,
  is present in the built app, and the real secret has zero tracked-file
  matches.
- 2026-08-19: After clearing all app state, the latest private Simulator build
  skipped manual setup, opened directly to the session list as `Connected`, and
  the bootstrapped host's `Test connection` result was `Reachable`.
- 2026-08-19: A separate build with the ignored private resource temporarily
  absent also completed successfully, preserving the manual-setup build path.
- 2026-08-19: Independent clean-install visual audit passed against the exact
  configured FlowDeck artifact. With no taps or typing, first launch showed a
  stable `Connected` session list. Evidence is under
  `.codex/evidence/20260819-231951-ios-visual-audit/`.
- 2026-08-19: The first-run setup host field now defaults to
  `https://lfg-pro.eugenechantk.me`; the full LFGCore suite passed 450 tests.
- 2026-08-19: TestFlight 1.3.0 build `202608192334` uploaded and reached
  `VALID` / `IN_BETA_TESTING` on the highest version train.

## Residual Risks

- The token can be extracted from an installed app or `.ipa`; this mechanism is
  only suitable for private distribution.
- Every device using the same build shares one revocation boundary until the
  token is rotated and the app is rebuilt.

## Bugs

- Fixed during verification: FlowDeck's explicit `-p ios` build and its saved
  project configuration used different derived-data caches. The independent
  auditor initially launched the stale cache and correctly reported manual
  setup. Rebuilding the exact saved-config artifact made clean-install evidence
  deterministic. Resource loading was also hardened to resolve the concrete
  folder-reference path under `bundle.bundleURL/PrivateResources`.
