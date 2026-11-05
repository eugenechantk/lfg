# Claude long-run interruptions

Session: b7c3ad00-d4b2-40f7-b52d-c30ea58bc314, Paywall checkout optimization.
Installed Claude Code: 2.1.280.

## Confirmed causes

The transcript records three API errors. Times below use Hong Kong time.

- October 18, 00:32: Five-hour account limit. The transcript says extra usage was disabled at organization level.
- October 19, 11:02: Fable model limit. Claude requested usage credits or a model switch.
- October 20, 20:52: The response stopped arriving. The transcript marks server_error and truncatedAfterOutput=true.

The latest error means the stream stalled while the connection stayed open. It does not identify whether Anthropic or the network caused the stall. No evidence establishes a process crash or context overflow. Automatic compaction succeeded earlier.

At inspection, the same session was active, waiting for one background verifier. It was not restarted or sent a message.

## Applied mitigation

Updated the existing user settings file at /Users/eugenechan/.claude/settings.json:

- CLAUDE_CODE_RETRY_WATCHDOG=1: wait through capacity errors and extend retries for other transient failures.
- CLAUDE_STREAM_IDLE_TIMEOUT_MS=600000: allow ten minutes before aborting a silent stream.

Read-back validation passed. No billing, model, account, schedule, or application source settings changed. Runtime adoption by the existing session was not directly verified. New sessions load these settings; current documentation says running sessions reload changed env settings, except features that read variables only at startup.

These settings do not guarantee completion. Spend limits and exhausted credits can still stop requests. Partial responses in interactive sessions can still require a new continuation turn.

## Recommended LFG follow-up

Add a durable recovery check for explicit transient API errors. Do not infer failure from silence or automatically continue normal final answers.

1. Identify an error using structured transcript metadata.
2. Wait until the turn has stopped and any child agents have settled.
3. Recheck session ownership, newer user input, queued input, and the current error ID.
4. Record one continuation attempt for that error before delivery. Reconcile uncertain delivery before retrying.
5. Ask Claude to inspect completed tool results and external receipts, then continue the original task without repeating confirmed actions.
6. Use bounded backoff and a retry budget. Stop for user cancellation, authentication, spending decisions, or unclear external effects.
7. Notify the user when recovery is exhausted. Never report success from process exit alone.

This follow-up is a recommendation, not an implemented feature.

## Sources

- https://code.claude.com/docs/en/errors#the-response-above-may-be-incomplete
- https://code.claude.com/docs/en/env-vars
- Local transcript errors are extracted in errors.json.
- Previous values for the changed settings are in settings-before.json.
