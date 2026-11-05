# Session notifications rollout

Pro is updated. Air remains pending because it is unreachable.

| Target | Result | Evidence |
| --- | --- | --- |
| Pro host | Restarted on the frozen release | Host identity unchanged; 31 scheduled tasks and 37 terminal sessions preserved |
| Pro Mac app | Installed at /Applications/lfg.app and running | Eight bundle files match; stable Developer ID signature; 282 checks pass |
| Pro MCP | Restarted | notify_session appears in tools/list |
| Air host and app | Pending connectivity | SSH handshake fails; authenticated API returns HTTP 530; local discovery finds no Air |

The staged release preserves the already-deployed offline-chat fix. It passed 198 backend tests and TypeScript checks.
The old host release and desktop bundle remain available for rollback. No commit or push occurred.

The live push test completed with 158 APNs acceptances and 4 rejections across 162 registrations.
The host reported four sandbox registrations rejected with DeviceTokenNotForTopic. Physical delivery and native banner rendering remain unverified.
The CLI timed out during the large fanout. Retrying its saved request ID returned the original receipt without resending.

Air packages: air-host-update.tar.gz and desktop-update.tar.gz. Both carry recorded SHA-256 hashes in release-state.json.
Bring Air online, then continue the already-authorized host restart and Mac app installation.
