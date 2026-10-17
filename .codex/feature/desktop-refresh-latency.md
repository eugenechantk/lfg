# Desktop refresh latency and task footer removal

Product tier.

## User story

Running sessions should appear promptly in the desktop list. Task loading and empty pages should omit the host requirement disclaimer on desktop and iPhone.

## Success criteria

- [x] SC1: A fast host publishes its live sessions within two seconds while another host or history takes eight seconds. Verify with a disposable HTTP fixture and the production store probe.
- [x] SC2: New sessions are discovered during an unrelated slow refresh. Existing sessions retain immediate start and completion updates. Verify temporal transport fixtures and native regression checks.
- [x] SC3: Late snapshots, reconnects, and history updates preserve current live status and closed history. Verify transport fixtures and native checks.
- [x] SC4: The disclaimer is absent on desktop and iPhone task loading and empty pages. Verify native rendering and iPhone simulator evidence.
- [x] SC5: Install the verified desktop build locally and compare live running rows with the host. Verify executable checksum, running process, and native UI.

## Decision log

The installed Pro executable lacks the existing live-feed probe and synchronization implementation. The latest built source has the feed but took 5.64 seconds to publish Pro rows while Air was offline. Refresh currently waits for sequential history requests and all hosts. Separate live refresh from history and publish each host independently. Preserve provider lifecycle logic and the current ten-second recovery interval.

The existing desktop target uses its repository swiftc build script and has no Xcode project. FlowDeck configuration points to the separate iOS target. Use the desktop script for this target and FlowDeck for iPhone verification.

The first Air SSH probe failed with a bad handshake. Later native probes connected to Air. This task did not change transport configuration or interrupt host services.

## Verification evidence

- Baseline fixture failed SC1: no rows appeared within two seconds when remote info and history took eight seconds. `regression-before.log` records the failure.
- Final signed desktop build passed (`build-final.log`). All 208 native checks passed (`desktop-tests.json`), including start/completion/prompt preservation during list republication.
- Fifteen temporal integration checks passed (`integration-result.json`). Initial healthy-host rows: 0.507 seconds; new live discovery: 0.193 seconds; completion: 0.114 seconds. Delayed snapshots, reconnect repair, cursor reset, and failed REST during streaming all passed.
- First real-host probe during concurrent builds produced no rows in twelve seconds. A fresh probe without changes produced Pro rows in 0.446 seconds and connected both hosts. This transient is retained in the logs; its cause was not proven.
- Installed candidate SHA256: `759b01cfbf44ee25ca695f40ade7ab742c87344ac26bd05ca8ed2ff6f96f23c0`. Developer ID signature verified before and after replacement. The previous installed bundle is backed up. Installed native checks repeated: 208 passed. See `install.json`.
- The installed GUI displayed four Working rows: three on Pro and one on Air (`installed-after.png`). All three running Pro IDs matched the live host snapshot (`installed-live-verification.json`). The installed probe published Pro rows after 1.505 seconds and connected both hosts.
- Independent iPhone audit: PASS for genuine task loading and empty states. FlowDeck build/install passed. Screenshots and accessibility trees confirm the disclaimer is absent. See `iphone-audit/evidence.md`.
- Independent desktop audit: PASS. A separate fixture repeated all fifteen timing checks and 208 native checks. Same-window captures verified starts, completions, and prompts after eight-second history publication, including visible closed history. Desktop task loading and empty screenshots omit the disclaimer. See `desktop-audit/evidence.md`.

Evidence root: `.codex/evidence/desktop-refresh-latency/`.

## Residual risks

The implementation was verified in Simulator. A follow-up request now authorizes commits, desktop installation on Pro and Air, and a new TestFlight release. Physical iPhone installation is outside the release verification.
