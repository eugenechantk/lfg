---
name: request-phone-sign-in
description: Request a website sign-in from Eugene's iPhone when a browser task is blocked by login, password entry, passkey, or two-factor authentication. Use before giving up or asking Eugene to type a URL. Supports Claude in Chrome and an existing Playwright browser through LFG.
argument-hint: <website URL>
---

# Request phone sign-in

When a browser task reaches a login wall, pause actions in that browser and request help through LFG. Do not ask for passwords, OTPs, cookie exports, or account credentials in chat. The phone opens a fresh website session; Eugene signs in and taps Done. All exportable cookies in that session go to the exact selected browser. The waiting command returns only delivery metadata, then you check the website and resume the original task.

## Identify this session and the browser

The host-side command is:

```sh
bun "__LFG_CLI__" browser-sign-in targets
bun "__LFG_CLI__" browser-sign-in sessions
```

Use your current `CODEX_THREAD_ID` when present. For Claude, identify the exact current session using the CLI list plus the current tmux pane (`tmux display-message -p -t "$TMUX_PANE" '#{session_name}:#{window_index}.#{pane_index}'`). Match its `tmuxTarget`. If multiple sessions still match, resolve the current session identity before creating a request; do not guess based on the working directory alone.

Choose the target for the browser you are already controlling. For Claude in Chrome, this is the companion extension in that exact Chrome profile. For Playwright, attach the existing context with `connectPhoneSignIn` or the local-CDP bridge documented in `__LFG_REPO__/extensions/phone-sign-in/README.md`. Do not create a different browser for the login, route a Playwright task to personal Chrome, select by list position, or guess between similarly named profiles. If the correct browser is absent, connect its adapter first.

## Request and wait

```sh
bun "__LFG_CLI__" browser-sign-in request \
  --session '<exact session ID>' \
  --target '<exact browser ID>' \
  --url 'https://website.example/login'
```

Use the actual login URL for the blocked task. Avoid credentials in URLs. The command prints the request ID and waits up to 16 minutes. While the request is `waiting` the session itself reads **needs input** in every LFG client, a push notification goes to the phone (the same one an AskUserQuestion sends), and the session shows a **Sign in to <website>** panel — so a one-line note that you are waiting on the phone sign-in is enough; do not ask Eugene to open anything. Keep the command alive using your tool's background-session/polling support. A yield or tool timeout does not mean the user declined. If the command is interrupted, reconnect with:

```sh
bun "__LFG_CLI__" browser-sign-in wait '<request ID>'
```

Use `status '<request ID>'` to inspect, or `cancel '<request ID>'` when you no longer need the login. `request --no-wait` is available when the caller needs the ID immediately. Do not create repeated requests while one is waiting.

## Resume based on the result

- `installed`: the cookies reached the chosen browser. Navigate/refresh the originally requested protected page (not just a fixed `/login` page), confirm authenticated content, then continue the user's original task. Do not claim website sign-in succeeded merely from the cookie count.
- `cancelled` or `expired`: report the result and wait for user direction; do not repeatedly re-prompt.
- `offline`: the original browser identity is gone. Reconnect that exact adapter and create a new explicit request only if sign-in is still needed. Never silently retarget.
- `partial` or `unknown`: check the destination before retrying; some cookies may already have arrived.
- `failed`: no confirmed complete delivery. Check extension permissions and the actual browser, then report the concrete issue.
- after host restart: waiting requests appear as expired and an interrupted delivery as unknown in the session’s sign-in history. Never replay cookies. A missing request may have aged out of the bounded history.

The system transfers cookies only. Embedded OAuth restrictions, localStorage-only sessions and device-bound credentials may require signing in directly on the Mac. Browser Stream is currently hidden. The agent receives no passwords or cookies in tool output or transcripts.

## Debug mode

When invoked with `[DEBUG]`, write a concise diagnostic log to `.codex/debug/request-phone-sign-in-<timestamp>.md` in the current working directory. Record the chosen session ID, target ID/name, website hostname (omit URL query strings), request ID, timestamps, state transitions, delivery counts, and the protected-page verification outcome. Record short decision summaries and errors/recovery steps. Never record passwords, OTPs, cookie names/values, pairing tokens, Cloudflare credentials, request bodies, private page contents, or full browser responses. This skill does not spawn agents.
