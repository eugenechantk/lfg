# Feature: Host and Model in chat options

## User story

Open a durable chat's More options sheet and find its Host and Model alongside the other chat controls, as in Sessions.

## Success criteria

- [x] Model is a direct selector in the options sheet, showing the saved choice and models advertised by the current host. Verify with a recorded native flow and fixture model catalog.
- [x] A model change saves to this chat and appears after reopening. Other saved profile fields remain unchanged. Verify against fixture receipts and native reopening.
- [x] Failed model changes leave the saved choice intact and show an error. Verify with an isolated offline fixture.
- [x] The Host control reflects the chat's actual execution owner. It shows the current host name and address, and explains the transfer limit. Verify in native UI against the owning fixture host, including offline access.

## Implementation and decisions

Use the existing chat options sheet and model picker. The backend currently supports Claude durable chats, so offer its advertised Claude models. Preserve the existing model editor and composer entry points.

The regular Session Host picker performs a transfer. Durable chat transfer is not implemented. Asked whether to expose current-host information now or include manual transfer. With no reply, proceed with the smaller UI scope: editable Model plus a current Host information panel. Manual transfer remains outside this change unless requested. This assumption was stated in the progress update.

Inline model changes save only the model against the saved profile, so they cannot accidentally commit unsaved text from another settings page.

## Verification evidence

- Eleven existing chat client tests pass, including host model discovery, profile settings and error propagation. `.codex/feature/chat-host-model-options-tests.txt`.
- FlowDeck iOS build passed at 08:32:24 UTC. `.codex/feature/chat-host-model-options-build-final.jsonl`.
- FlowDeck standalone Mac compile passed at 08:34:23 UTC. `.codex/feature/chat-host-model-options/mac-build.jsonl`.
- The first Mac self-test run lacked canonical menu artwork because the temporary XcodeGen project has no resource phase. After adding the unchanged source resources, the second run passed all 287 desktop checks. `.codex/feature/chat-host-model-options/mac-tests.txt`.
- Independent native audit PASS: `.codex/evidence/chat-host-model-options/evidence.md`. The recording proves the host catalog, model save/reopen, preservation of saved instructions and memory, isolation of unsaved drafts, current Host details and offline access, and failed offline saves preserving the last model with no alternate-host writes.
- Restored the original FlowDeck LFG Debug / iPhone 17 Pro selection after the temporary Mac compile.
- The final shared source hash matches the audited build. No commit, deployment or TestFlight release was made.
