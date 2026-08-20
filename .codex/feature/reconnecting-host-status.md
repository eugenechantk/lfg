# Feature: Reconnecting Host Status

## User Story

As a multi-host iOS user, I want a host that is still establishing a connection to appear gray and reconnecting rather than orange and offline, so app launch does not look like an outage.

## User Flow

1. Open or foreground the app.
2. Each host starts reconnecting immediately.
3. A host is gray and announced as reconnecting until it provides live evidence.
4. The host becomes green when live, or orange only after reconnection finishes and sustained failure is established.

## Success Criteria

- SC1: Unknown, connecting, degraded, and transient no-network host states present as reconnecting.
- SC2: A live host presents as connected.
- SC3: Sustained offline/no-network states present as reconnecting during an active reconnect burst, then offline afterward.
- SC4: Every rendered multi-host indicator uses gray/reconnecting, green/online, and orange/offline consistently.
- SC5: Transport timing and health-state behavior are unchanged.

## Test Strategy

Unit-test the platform-neutral mapping from host health plus reconnect activity to the three presentation states. Validate both multi-host SwiftUI surfaces in Simulator.

## Tests

### Package Unit

- `ios/LFGCore/Tests/LFGCoreTests/HostConnectionPresentationTests.swift`
  - transient states map to reconnecting — SC1
  - live maps to connected — SC2
  - sustained failures map according to reconnect activity — SC3

### Simulator

- Confirm the rendered multi-host header tokens expose the correct reconnecting/online/offline labels and colors — SC4.

## Implementation Details

- Add a shared `HostConnectionPresentation` mapping in `LFGCore`.
- Use the mapping for the aggregate single-host badge and rendered multi-host header tokens.
- No changes to reconnect scheduling, probing, or host-state reduction.
- Implemented in `HostState.swift`, `SessionStore.swift`, and `SessionListView.swift`.
- Multi-host accessibility labels now distinguish online, reconnecting, and offline.
- Removed the obsolete, unreferenced `StatusBadge`/`HostStatusChip` duplicate found during visual audit.

## Residual Risks

None known. The pure mapping is covered by Swift tests. The independent
Simulator audit passed after observing the healthy host green, the actively
retried unavailable host gray, and that host turning orange after sustained
failure. Evidence: `.codex/evidence/20260820-125658-ios-visual-audit/`.

## Bugs

- The initial spec treated an unreferenced `StatusBadge` declaration as a second
  rendered surface. The independent audit caught that it is dead code; it was
  removed and SC4 now describes the actual user-visible surface.
