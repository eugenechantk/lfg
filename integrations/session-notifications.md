# Session notifications

Send one clear result or request for input to every registered iPhone and iPad,
and every connected Mac running the updated LFG client.

```sh
lfg notify sessions
lfg notify --session <session-id> --status completed \
  --message 'Fixed notification copy. All tests pass. The host still needs deployment.' \
  --request-id notification-copy-result-1
```

Use `bun run /path/to/lfg/src/cli.ts` if `lfg` is not on PATH.
Match the exact session ID or tmux name. Do not infer identity from the working directory alone.
New managed sessions receive these instructions automatically.

Statuses: `working`, `completed`, `needs-input`, `blocked`, `reminder`.
The status describes the alert; it does not change actual execution state.
Keep the message within 500 characters. The title defaults to the session name;
`--title` overrides it, up to 80 characters.

Use concrete copy: “Build uploaded. Apple processing is pending.”
For input, say what is needed: “Choose which two screenshots to submit.”
Avoid routine progress alerts. Use scheduled Tasks for future reminders.

The CLI prints the request ID before sending. Reuse that ID after a timeout.
The host keeps retry receipts for up to 14 days, capped at 10,000 notifications.
An identical retry returns the existing receipt and does not resend.
Each mobile device receives an independent attempt. A failed device does not prevent another attempt.
Receipts report APNs acceptance, never proof that a person saw an alert.
Mac delivery uses the existing resumable event feed. The Mac must be running.

MCP: `notify_session` takes `session_id`, `request_id`, `status`, `message`, and optional `title`.
HTTP: `POST /api/sessions/<id>/notify` takes `requestID`, `status`, `message`, and optional `title`.

Custom completion suppresses the generic stop alert for that same user turn.
Automatic alerts use current assistant prose when available, with the existing generic fallback.
Older Mac clients need an update. iPhone and iPad render the custom APNs copy without a new app build.
