# Feature: Bundled Pro and Air Hosts

## User Story

As the sole LFG user, Eugene can install either Apple client and immediately connect to both the Pro and Air through their Cloudflare-protected LFG endpoints without typing either URL or credential.

## User Flow

1. Install or update LFG.
2. Launch the client.
3. See Pro and Air as configured hosts.
4. The client sends the bundled Cloudflare Access service credential to either endpoint.
5. Desktop session opening uses the matching `pro` or `air` Cloudflare SSH alias.

## Success Criteria

- SC1: The private iOS/iPadOS bundle declares both `https://lfg-pro.eugenechantk.me` and `https://lfg-air.eugenechantk.me` while continuing to accept the legacy one-host payload.
- SC2: iOS stores the bundled credential for both origins and adds both hosts without duplicates, preserving an existing default host.
- SC3: A fresh desktop configuration contains both hosts with names `Pro`/`Air`, SSH aliases `pro`/`air`, and forced SSH transport; an existing non-empty host file is not rewritten.
- SC4: The desktop credential fallback authorizes only origins explicitly listed by the private payload and accepts the legacy one-host payload.
- SC5: The iOS app and widget ship as marketing version `1.3.0`.
- SC6: A verified TestFlight 1.3.0 build becomes available to internal testers.
- SC7: The rebuilt desktop app is installed and running on both Pro and Air with credentials for both Cloudflare origins.

## Test Strategy

- Swift Testing covers payload decoding, canonicalization, legacy compatibility, duplicate suppression, and default preservation.
- The desktop headless feature suite covers bundled host metadata, fresh-install seeding, existing-config preservation, and exact-origin credential fallback.
- FlowDeck builds/tests the iOS targets. Because the host list changes visibly on a clean install, an independent simulator audit verifies that both hosts appear.
- The canonical Fastlane deploy and verification lanes prove the uploaded build number, version train, processing state, and internal TestFlight availability.
- Desktop build hashes, signatures, processes, credentials, and live APIs are checked on both Macs.

## Tests

### Package Unit

- `ios/LFGCore/Tests/LFGCoreTests/BundledCloudflareAccessTests.swift`
  - decodes a two-host payload in order
  - accepts the legacy single-host payload
  - rejects unsafe or empty host sets
  - adds all missing hosts without duplication
  - preserves an existing default

### Desktop Headless

- `desktop/LFGSessions.swift --desktop-feature-test`
  - validates Pro and Air bundled entries
  - seeds both entries for a fresh configuration
  - preserves an existing non-empty configuration
  - accepts multi-origin and legacy fallback payloads without crossing origins

## Implementation Details

- Use one service credential with an ordered allowlist of HTTPS origins; do not duplicate secrets per host in the bundle.
- Keep `hostURL` in the generated JSON for backward compatibility and add `hostURLs` for current clients.
- Pro remains first and therefore the default only on a clean iOS install.
- Desktop seeds both Cloudflare entries only when no non-empty host file exists.

## Residual Risks

- The service credential remains extractable from the private TestFlight binary, as explicitly accepted for this single-user app.
- Air cannot import into its GUI login Keychain from a non-interactive SSH session (`errSecInteractionNotAllowed`), so its installed desktop app uses the mode-`0400` exact-origin fallback. The app verified both origins through that fallback.

## Verification

- `swift test` in `ios/LFGCore`: 93 tests passed.
- Desktop `--desktop-feature-test`: 105 assertions passed.
- FlowDeck simulator build: passed.
- Independent clean-install iOS visual audit: PASS; Pro and Air online, both URLs in Settings, Pro alone marked Default. Evidence: `.codex/evidence/20260820-014943-ios-visual-audit/evidence.md`.
- Signed IPA: version `1.3.0`, build `202608200149`, both bundled origins and a non-empty private credential present.
- TestFlight definition-of-done: `VALID`, highest train `1.3.0`, `IN_BETA_TESTING`.
- Desktop 1.3.0: identical signed binary installed and running on Pro and Air; both live probes reported `hostsReachable: 2`.

## Bugs

_None yet._
