# Desktop Pro host default

## User story

As Eugene, I want the macOS desktop client's Add Host form to start with the
production Pro Cloudflare URL so configuring the Air does not require recalling
or retyping the domain.

## User flow

1. Open the desktop client's Hosts settings.
2. The new-host URL field contains `https://lfg-pro.eugenechantk.me`.
3. Its SSH field contains the stable `pro` alias.
4. Add it; the entry receives the friendly name `Pro` and forces plain SSH so
   Cloudflare Access is never bypassed by Mosh's UDP transport.
5. Existing configured hosts remain unchanged.

## Success criteria

- [x] SC1: The canonical desktop Pro entry uses the production Cloudflare URL
  and the label `Pro`. **Verify by:** `--desktop-feature-test` assertion.
- [x] SC2: Hosts settings initializes its new-host field from that canonical
  entry without modifying saved hosts. **Verify by:** source inspection plus
  isolated runtime UI audit.
- [x] SC3: Adding the canonical URL persists the `Pro` display name while other
  URLs retain existing behavior. **Verify by:** `--desktop-feature-test` assertion.
- [ ] SC4: The canonical Pro entry persists `ssh: "pro"` and
  `transport: "ssh"`, while legacy entries default to automatic Mosh/SSH.
  **Verify by:** `--desktop-feature-test` assertions and persisted-config audit.
- [ ] SC5: A Cloudflare-backed row generates a plain SSH tmux-attach command
  even when Mosh is installed locally. **Verify by:** `--desktop-feature-test`
  command-selection assertion.
- [ ] SC6: Desktop API requests attach a per-origin Cloudflare Access service
  token loaded from macOS Keychain, and the token is absent from host JSON and
  Git. **Verify by:** request-construction assertions, credential-status CLI,
  secret scan, and live protected API request.

## Platform and stack

- macOS 26, SwiftUI/AppKit, single-file Swift app built by `desktop/build.sh`.

## Decision log

- Prefill the form rather than silently migrating every existing host file.
  This preserves the user's current multi-host topology and makes adding Pro an
  explicit action.
- Keep the URL and display name in one canonical `Config.preferredHost` value so
  the form, persistence behavior, tests, and documentation cannot drift.
- Model transport explicitly instead of inferring it from a hostname. Cloudflare
  Access proxies SSH over WebSockets; Mosh only uses SSH to bootstrap and then
  switches to a separate UDP connection that the tunnel does not publish.
- Store desktop Access credentials in Keychain keyed by canonical HTTPS origin.
  The host list remains safe to sync and the same private provisioning file can
  authorize Pro and Air when both Access applications allow that service token.

## Verification evidence

- `desktop/build.sh` completed and the signed app bundle was rebuilt.
- `build/lfg.app/Contents/MacOS/lfg --desktop-feature-test` passed 86 assertions.
- An isolated Tier-2 AX run resolved `host_url_field` with value
  `https://lfg-pro.eugenechantk.me`; screenshot:
  `.codex/evidence/desktop-pro-host-default/hosts-settings.png`.
- Pressing Add in the isolated config persisted localhost plus
  `{"displayName":"Pro","url":"https://lfg-pro.eugenechantk.me"}` and the
  second row exposed `host_display_name_field_1` with value `Pro`.

## Bugs

_None._
