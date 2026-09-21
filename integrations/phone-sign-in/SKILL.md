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

Choose the target for the browser you are already controlling. A headless browser started with the launcher (next section) is such a browser; one started any other way is not a valid target, so restart it through the launcher instead. For Claude in Chrome, this is the companion extension in that exact Chrome profile. For Playwright, attach the existing context with `connectPhoneSignIn` or the local-CDP bridge documented in `__LFG_REPO__/extensions/phone-sign-in/README.md`. Do not create a different browser for the login, route a Playwright task to personal Chrome, select by list position, or guess between similarly named profiles. If the correct browser is absent, connect its adapter first.

## Headless browsers: always start them through the launcher

Any headless browser you launch yourself — for a task that might meet a login, or as the approved fallback when Eugene is away and Claude in Chrome cannot get past a login wall — MUST be started with the launcher, never by hand:

```sh
__LFG_REPO__/scripts/browser-sign-in-headless.sh start "What this browser is for"
# -> {"id":"02cda7","cdp":"http://127.0.0.1:9333","targetId":"…","dir":"~/.lfg/headless/02cda7",…}
__LFG_REPO__/scripts/browser-sign-in-headless.sh list
__LFG_REPO__/scripts/browser-sign-in-headless.sh stop <id>      # or --all
```

`start` launches Playwright's headless Chromium on a loopback-only debugging port with a private owner-only profile, attaches the LFG adapter, and returns only once the browser is listed as a sign-in target. Use the printed `targetId` with `request` below — that is the "Sign in on iPhone" option, available from the first moment the browser exists. The adapter reads the connection token itself; never read, print or paste the token.

- **Drive it from Node, not Bun.** `chromium.connectOverCDP` hangs under Bun (the launcher already works around this for the adapter). Put your driver `.mjs` files in the printed `dir` — it has a `node_modules` symlink so `import { chromium } from "playwright-core"` resolves — and connect to the printed `cdp` URL.
- **A missing token means first-time setup on this Mac:** `(cd __LFG_REPO__ && bun scripts/browser-sign-in-setup.ts >/dev/null)` creates it without displaying it. The Chrome-extension target is different: if `targets` is empty for Claude in Chrome, the extension was never installed in that profile, which needs Eugene at the keyboard once (chrome://extensions cannot be automated, and you do not paste tokens). Do not dig further — use the launcher or tell him.
- **Verify, then act.** `installed` only means cookies arrived; a sign-in closed early delivers a partial set (seen: 5 cookies vs 15 for a complete Apple ID session). Load the protected page and confirm account content before doing anything.
- **Fill, read back, assert, then submit** as separate steps for anything that changes state, and match destructive-adjacent buttons by exact name.
- **Always `stop` when the task ends.** The profile holds real login sessions; `stop` kills both processes and deletes it. Never leave one running between tasks, never reuse one across unrelated tasks.

Worked end to end 2026-09-21 for Apple Developer + App Store Connect (both honour the transferred Apple ID session).

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
- `failed`: no confirmed complete delivery. Read `result.reason` first — `permission-missing:<origin>` means the extension's Allowed websites list lacks that site; `set-rejected:<cookie>@<domain>:<message>` means the browser refused that cookie; `busy`, `timeout`, `browser-disconnected` and `Browser is offline…` mean the transfer never landed. Report that concrete reason; do not guess at permissions when the reason says otherwise.
- after host restart: waiting requests appear as expired and an interrupted delivery as unknown in the session’s sign-in history. Never replay cookies. A missing request may have aged out of the bounded history.

The system transfers cookies only. Embedded OAuth restrictions, localStorage-only sessions and device-bound credentials may require signing in directly on the Mac. Browser Stream is currently hidden. The agent receives no passwords or cookies in tool output or transcripts.

## Debug mode

When invoked with `[DEBUG]`, write a concise diagnostic log to `.codex/debug/request-phone-sign-in-<timestamp>.md` in the current working directory. Record the chosen session ID, target ID/name, website hostname (omit URL query strings), request ID, timestamps, state transitions, delivery counts, and the protected-page verification outcome. Record short decision summaries and errors/recovery steps. Never record passwords, OTPs, cookie names/values, pairing tokens, Cloudflare credentials, request bodies, private page contents, or full browser responses. This skill does not spawn agents.
