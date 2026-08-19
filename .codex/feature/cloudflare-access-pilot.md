# Feature: Cloudflare Access pilot

## User Story

As the owner of LFG, I want the iOS client to reach this Mac through a secure
Cloudflare Tunnel so that the phone no longer depends on Tailscale while the Mac
continues running Surfshark.

## User Flow

1. Eugene creates or edits this Mac in LFG Settings.
2. He enters the Cloudflare hostname plus the per-device Access client ID and
   secret; the secret is stored in Keychain, not the host JSON.
3. Test Connection authenticates through Cloudflare Access.
4. Normal REST calls, the resumable SSE stream, background sends, uploads,
   browser previews, images, files, and videos use the same host credential.
5. Anonymous internet requests are rejected at Cloudflare and never reach LFG.
6. `lfg serve` remains loopback-only; `cloudflared` is the only ingress path.

## Success Criteria

- [x] SC1: An optional Cloudflare Access credential is applied to every
  same-origin LFG request, including REST, SSE, prepared background sends,
  uploads, and resource downloads, while external URLs never receive it. —
  **Verify by:** LFGCore request-capture tests.
- [x] SC2: Host credentials are stored in iOS Keychain, survive host edits, and
  are removed with the host; neither the secret nor client ID is encoded in the
  persisted `Host` JSON. — **Verify by:** host serialization tests, Keychain
  integration probe in Simulator, and source audit.
- [x] SC3: Images, browser previews, documents, and videos no longer use
  unauthenticated direct host fetches; large video playback uses an
  authenticated file download rather than buffering the entire asset in
  memory. — **Verify by:** LFGCore resource-request tests, source audit, and
  Simulator interaction.
- [x] SC4: `https://lfg-pro.eugenechantk.me` is backed by a named Cloudflare Tunnel to
  `http://127.0.0.1:8766`, with Access default-deny protection; anonymous
  `/api/sessions` is rejected and the configured service token receives LFG
  JSON. —
  **Verify by:** unauthenticated and authenticated `curl` probes plus tunnel
  status.
- [x] SC5: LFG listens only on loopback after cutover, Cloudflare remains
  reachable, and Surfshark remains running. — **Verify by:** `lsof`, process
  inspection, loopback probe, and authenticated public probe.
- [x] SC6: Hosts without Cloudflare credentials continue generating unchanged
  requests and remain compatible with LAN/Tailscale URLs. — **Verify by:**
  regression tests and the existing LFGCore suite.
- [x] SC7: The host editor clearly supports Cloudflare Access credentials and
  never displays a stored secret after save. — **Verify by:** Simulator UI flow
  and independent iOS visual evidence audit.

## Test Strategy

- LFGCore unit/integration tests capture requests from all request-producing
  paths and assert exact credential propagation and same-origin scoping.
- Existing HostStore tests prove credentials never enter Host Codable state.
- Simulator verification exercises add/edit/test/save and credential clearing.
- Live Cloudflare probes prove edge denial and authenticated reachability.

## Tests

### Package unit/integration

- `ios/LFGCore/Tests/LFGCoreTests/CloudflareAccessTests.swift`
  - credential header application and omission
  - same-origin resource request scoping
  - REST, prepared background-send, upload, and SSE request coverage
- Existing `MultiHostTests` and full LFGCore suite — regression coverage.

### Runtime

- FlowDeck build/run on the configured iPhone 17 Pro Simulator.
- Independent `ios_visual_evidence_auditor` review of Host Settings.
- Live named-tunnel and Access probes against this Mac.

## Implementation Details

### Phase 1: Authenticated client plumbing

- Add a value-type Cloudflare Access credential to LFGCore.
- Centralize same-origin URLRequest authentication in `LFGClient`.
- Add authenticated resource data/download APIs.
- Cover every explicit URLRequest constructor with tests first.

### Phase 2: Keychain and host settings

- Add an app-target Keychain credential store keyed by canonical host URL.
- Wire `AppSettings.client(for:)` and `defaultClient` through that store.
- Add Client ID / Client Secret controls to the host editor.
- Migrate credentials when a host URL changes and delete them with the host.

### Phase 3: Authenticated rich media

- Replace direct `URLSession.shared` and `AsyncImage` host loads.
- Download authenticated videos to a temporary file before AVPlayer playback.
- Preserve direct unauthenticated loading for genuinely external URLs.

### Phase 4: Cloudflare pilot cutover

- Create `lfg-pro` named tunnel and DNS route.
- Create a default-deny Access application plus per-device Service Auth token.
- Run `cloudflared` persistently on this Mac. Keep Surfshark routing unchanged
  while the tunnel remains healthy; add a Bypasser exception only if later soak
  testing proves it necessary.
- Bind LFG to loopback only after authenticated public probes pass.

## Decision Log

- Keep the existing REST/SSE/cursor architecture. It already reconnects
  losslessly and does not need a relay.
- Use Cloudflare Access as the pilot security boundary instead of adding LFG
  server authentication. The loopback-only origin prevents bypassing Access.
- Store one service token per device in Keychain. Host JSON remains safe to sync
  or inspect.
- For the pilot, download protected videos to a temporary local file. Apple's
  supported AVURLAsset API accepts cookies but not arbitrary Access headers;
  the commonly used HTTP-header option is unsupported.

## Residual Risks

- Cloudflare availability becomes part of the public path.
- A stolen device service token grants the same LFG access until revoked.
- The final physical-device cellular soak is separate from Simulator proof.

## Verification Evidence

- 2026-08-19: `swift test` in `ios/LFGCore` passed 361 XCTest cases plus
  84 Swift Testing cases. The seven new Access request tests passed.
- 2026-08-19: FlowDeck built the LFG scheme successfully for dedicated
  Simulator `98E06132-4DDD-40B5-8D66-825C82135EEC` after the Keychain and
  first-run credential UI changes.
- 2026-08-19: FlowDeck launched the app and verified the first-run Access
  toggle reveals the Client ID and secure Client Secret controls. A dummy
  secret rendered masked in the simulator capture.
- 2026-08-19: Created named tunnel `lfg-pro`
  (`601ee1ba-ec98-4251-8663-1db68ed61cdc`), validated its ingress config, and
  installed a LaunchAgent that maintains four active edge connections. The DNS
  route points at the named tunnel, whose origin is `http://127.0.0.1:8766`.
- 2026-08-19: Created the `LFG Pro` Access application with a Service Auth
  policy scoped to the per-device `LFG iPhone – Pro pilot` token. Anonymous
  `/api/sessions` requests return HTTP 403; authenticated requests return HTTP
  200 and live LFG JSON.
- 2026-08-19: Authenticated `/api/events?since=0` returned HTTP 200 and an SSE
  event before remaining open until the six-second probe timeout.
- 2026-08-19: Restarted LFG after changing its bind setting from `0.0.0.0` to
  `127.0.0.1`. Loopback returns HTTP 200, the former LAN address refuses direct
  connections, and authenticated Cloudflare requests continue returning HTTP
  200.
- 2026-08-19: Surfshark remained connected over WireGuard throughout the live
  Access, REST, and SSE probes. No Bypasser exception was added because
  `cloudflared` is already stable through the VPN and weakening VPN coverage is
  unnecessary without contrary soak-test evidence.
- 2026-08-19: The dedicated Simulator used the real Service Auth token to show
  `Reachable`, saved the host, and loaded the live session list as `Connected`.
  Reopening the host editor showed the stored-secret replacement placeholder,
  not the secret value.
- 2026-08-19: Independent iOS visual evidence audit passed on the latest build
  with no deltas. Evidence is recorded under
  `.codex/evidence/20260819-230208-ios-visual-audit/`.

## Bugs

_None yet._
