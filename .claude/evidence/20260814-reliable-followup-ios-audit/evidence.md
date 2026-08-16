# iOS Visual Evidence Audit
Verdict: PASS
Timestamp: 2026-08-14 19:10:42 HKT
Repository: /Users/eugenechan/dev/personal/lfg
Simulator: cc-019fffcc-019ffff0 / B5F98E1F-102A-4B14-ACCB-5D9393EA04AF
App: com.eugenechan.lfg (FlowDeck app id C7214BDD-E0A1-41BD-B75E-3E24327E3300)

## Change Audited
Reliable follow-up delivery, specifically the iOS handling of queued-message `Remove` and `Edit` after the message has already been committed to Codex's native queue.

## Success Criteria
| Criterion | Result | Evidence |
| --- | --- | --- |
| A running Codex turn shows the follow-up as a local pending row instead of dropping it. | PASS | `02-native-queued-before-actions.png`, `02-native-queued-before-actions-tree.json`, `02-queue-before-actions.json` show `sleep 90` running while `QUEUE_AUDIT_NOTE...` remains in the pending strip and the server queue marks it `queued`. |
| Tapping `Remove` on an agent-committed/native-queued row does not make the local row disappear. | PASS | `03-after-remove.png`, `03-after-remove-tree.json` show the same pending row still visible after the `Remove` action. `03-queue-after-remove.txt` shows the row still exists server-side. |
| Tapping `Edit` on an agent-committed/native-queued row does not duplicate its text into the composer. | PASS | `04-after-edit.png`, `04-after-edit-tree.json` show the composer still at the empty `Message` placeholder while the `EDIT_AUDIT_NOTE...` row remains pending. |
| The server truth for that state is rejection, not successful removal. | PASS | `05-delete-delivered-row.txt` captures `HTTP 409` with `{"error":"message already delivered or in-flight"}` for the same delivered/in-flight queue item. |

## Artifacts
- `01-detail-idle.png`
- `01-detail-idle-tree.json`
- `02-native-queued-before-actions.png`
- `02-native-queued-before-actions-tree.json`
- `02-queue-before-actions.json`
- `03-after-remove.png`
- `03-after-remove-tree.json`
- `03-queue-after-remove.txt`
- `04-after-edit.png`
- `04-after-edit-tree.json`
- `04-queue-after-edit.json`
- `05-delete-delivered-row.txt`
- `05-after-direct-delete-proof.png`
- `05-after-direct-delete-proof-tree.json`
- `create-request.json`
- `create-response.json`

## Commands
- `flowdeck config get --json`
- `flowdeck run -S "B5F98E1F-102A-4B14-ACCB-5D9393EA04AF" --json`
- `flowdeck ui simulator session start -S "B5F98E1F-102A-4B14-ACCB-5D9393EA04AF" --json`
- `flowdeck ui simulator tap ...`
- `flowdeck ui simulator type ...`
- `curl http://127.0.0.1:8766/api/sessions/new`
- `curl http://127.0.0.1:8766/api/sessions/019ffff2-e185-7ae1-af67-c7b58d891c3e/queue`
- `curl -X DELETE http://127.0.0.1:8766/api/sessions/019ffff2-e185-7ae1-af67-c7b58d891c3e/queue/3dd62073c853141c`

## Notes
- The app does not visibly surface the rejection text in the UI. The rejection itself is proven by the direct `409` artifact, while the user-facing behavior is proven by the row remaining on screen and the composer staying empty.
- The first attempt at the `Edit` check lost the row at a tool boundary before the action sheet could be used. A second pass with a longer-running single tool call captured the stable pending state and the post-`Edit` blank composer.
- A cleanup `POST /api/sessions/019ffff2-e185-7ae1-af67-c7b58d891c3e/close` returned `{"error":"session not found"}` after evidence capture, indicating the disposable session was no longer available to close through that route.
