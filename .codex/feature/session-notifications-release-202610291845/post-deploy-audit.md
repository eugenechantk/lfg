# Post-deployment audit

Pro: PASS. Air: BLOCKED/PENDING. The requested two-Mac rollout is incomplete.

Checked at 2026-10-29T10:49:27.805899+00:00.
The Pro host runs from the staged release source. Its identity, 31 task configurations, and 37 existing tmux sessions remain preserved.
The invalid notification request returns 400 without changing notification receipts. MCP advertises notify_session.
The installed application matches all eight manifest hashes, passes strict signature verification, and runs from /Applications/lfg.app.
The source matches all 565 runtime hashes. The offline-chat capability and prior offline-chat backend files remain preserved.

The existing mobile receipt reports 162 attempts, 158 APNs acceptances, and four failures.
The parent identified the failure reason as DeviceTokenNotForTopic. Acceptance does not prove physical delivery.

Air remains unverified. An independent bounded SSH attempt failed with websocket: bad handshake.
The parent also reports origin status 530 and failed local discovery/SSH. No Air update is claimed.

This audit did not send notifications, unlock the screen, use the GUI, or mutate production state.
It wrote only this report. Staged evidence reports 198 host tests and 282 native checks.

The prior host snapshot contained backend files only. The audit compared those existing files and excluded absent client paths.

## Recorded checks

```json
{
  "host": {
    "status": 200,
    "hostId": "2b178534-9b81-413e-b75a-0f2e195fe45f",
    "preserved": true
  },
  "listener": {
    "pid": 92606,
    "count": 1,
    "cwd": "/Users/eugenechan/dev/personal/lfg/.codex/feature/session-notifications-release-202610291845/source",
    "expectedSource": true
  },
  "tasks": {
    "before": 31,
    "current": 31,
    "configurationPreserved": true
  },
  "tmux": {
    "before": 37,
    "current": 37,
    "missing": []
  },
  "invalidNotify": {
    "status": 400,
    "body": {
      "error": "requestID must contain 1 to 160 characters."
    },
    "receiptFileUnchanged": true
  },
  "mcp": {
    "status": 200,
    "tools": 23,
    "notify_session": true
  },
  "offlineCapability": {
    "clientChatIDs": true
  },
  "offlineBasePreserved": {
    "src/chat-api.ts": true,
    "src/chat-jobs.ts": true,
    "src/chat-claude.ts": true,
    "src/chat-native.ts": true,
    "src/chat-sessions.ts after removing only two notification additions": true
  },
  "runtimeManifest": {
    "files": 565,
    "mismatches": []
  },
  "desktop": {
    "manifestFiles": 8,
    "mismatches": [],
    "executableSHA256": "7e679179718e624a43a0d10772a7b10b336f6c7067de23c124838b2d7949d8ea",
    "codesignExit": 0,
    "codesign": "/Applications/lfg.app: valid on disk\n/Applications/lfg.app: satisfies its Designated Requirement",
    "runningPids": [
      "95153"
    ],
    "runningCommands": [
      "/Applications/lfg.app/Contents/MacOS/lfg"
    ]
  },
  "existingMobileReceipt": {
    "state": "partial",
    "attempted": 162,
    "accepted": 158,
    "failed": 4
  },
  "air": {
    "verdict": "BLOCKED/PENDING",
    "independentSshExit": 255,
    "independentSshError": "websocket: bad handshake; Connection closed by UNKNOWN port 65535",
    "otherParentReportedEvidence": "Authenticated API with native User-Agent returned 530; local mDNS/SSH failed. No Air deployment verified."
  }
}
```
