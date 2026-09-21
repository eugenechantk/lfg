# LFG Sign in on Phone

Send a login from LFG on iPhone/iPad to the **same normal Chrome profile** used by Claude in Chrome, or to an agent's existing Playwright context. No debugger permission, content scripts, Chrome restart, password transfer or agent transcript messages.

## Chrome setup

1. Use a host running this branch of LFG (`feature/phone-sign-in`). This change does not restart or deploy the host automatically.
2. On that Mac, run `bun scripts/browser-sign-in-setup.ts` from this repository. It creates a random connection token in `~/.lfg/browser-sign-in.token` with mode 0600. The explicitly invoked command displays the token for setup. Do not paste it into an agent chat.
3. In **the Chrome profile that contains Claude's extension**, open `chrome://extensions`, enable Developer mode, choose **Load unpacked**, and select this `extensions/phone-sign-in` directory.
4. Click the LFG extension icon to open its options. Give the browser a recognizable name, paste the connection token, and save. Keep port **8766** for your normal LFG host. The extension always connects to this Mac's loopback, never a remote URL.
5. Under **Allowed websites**, allow the domains you plan to send, or choose **Allow all websites** for all HTTPS sites. Agent-requested sign-ins send all exportable cookies from the isolated phone session; manual sign-in lets you select domains. Permission is requested only after your click. Remove permissions there when no longer wanted. A transfer for any unapproved domain fails before changing cookies. Every non-installed result carries a `reason` (`permission-missing:<origin>`, `set-rejected:<cookie name>@<domain>:<browser message>`, `busy`, `timeout`, …) in the CLI output, the phone's result screen and the extension's status line — cookie names and domains only, never values.

The token stays in Chrome extension-local storage, never sync storage. There are no content scripts or externally-connectable messages. All adapters on one Mac use the same local token; possession authorizes registration as a destination. Restart the host and reconnect adapters after deliberately rotating that token. Install in a second profile with a distinct browser name if you want both selectable. Incognito is unsupported.

## Agent-requested sign-in (primary flow)

Install the shared Claude/Codex skill with `bun scripts/install-phone-sign-in-skill.ts /path/to/lfg`. The global skill is `request-phone-sign-in`.

An agent hitting a login wall lists `bun src/cli.ts browser-sign-in targets`, identifies the browser it already controls, and runs:

```sh
bun src/cli.ts browser-sign-in request --session <session-id> --target <browser-id> --url https://website.example/login
```

The command waits for a result. LFG shows **Sign in to website.example** above that session's composer. Tap it and sign in. **Done** appears when cookies are available and the app detects account controls; use **I’m signed in** for sites it cannot recognize. Tap **Done** to send and close the sheet. The URL and target are already bound; all unexpired, exportable cookies from that fresh web session are sent, including login-provider domains. There is no browser picker or domain checklist in this flow. A successful acknowledgment releases the waiting command, and the agent must refresh/check the protected website before proceeding.

Requests expire after 15 minutes and never silently retarget after a browser reconnect. More → Sign in on iPhone opens a medium-height, session-scoped history sheet, with up to 128 recent records across the host. Completed entries show results; waiting entries reopen sign-in. The host saves website origins, destination names/IDs, timestamps and outcomes in `~/.lfg/phone-sign-in-history.json` (owner-only), never cookies or URL paths/query strings. After restart, pending requests become expired and in-progress deliveries become unconfirmed; neither is replayed. `status`, `wait`, and `cancel` take a request ID. There is one active request per browser; duplicates reuse the original request. Cookie payloads are never persisted or returned to the agent. Existing cookie count/size limits still apply; oversized exports fail instead of silently truncating.

The following manual flow remains available as a fallback.

## Phone flow

Open a session → **More → Sign in on iPhone → +**. Choose the connected browser, enter an HTTPS website, and sign in. Tap **Review**, select domains, then **Send sign-in**. The destination must still be online; reconnecting creates a new destination identity and requires reselection.

The phone transfers only the selected domains' cookies. A successful result confirms cookie installation, not that the website accepted the session. Refresh the destination website yourself, then tell Claude/Codex to continue. Pause automation before replacing its login. No tab is automatically reloaded or navigated.

## Playwright: existing context

Use this with the exact `BrowserContext` the agent already owns (Bun/TypeScript):

```ts
import { connectPhoneSignIn } from '/path/to/lfg/src/browser-sign-in-playwright.ts';
const bridge = connectPhoneSignIn(context, { name: 'Research browser' });
// When no longer needed:
bridge.close(); // Does not close the context or browser.
```

The bridge reads the local token file automatically. `baseURL` can override the default `http://127.0.0.1:8766` for a separate test host; remote adapter connections are rejected.

### Headless browser with sign-in built in (preferred for agents)

```sh
scripts/browser-sign-in-headless.sh start "Research browser"   # prints {id, cdp, targetId, dir}
scripts/browser-sign-in-headless.sh list
scripts/browser-sign-in-headless.sh stop <id> | --all           # kills it and deletes its profile
```

One command gives an agent a headless Chromium (loopback CDP, private 0700 profile under `~/.lfg/headless/<id>/`) that is already registered as a sign-in target, so **every headless browser has the Sign in on iPhone option from the start**. Drive it from Node with `chromium.connectOverCDP(cdp)`; driver files placed in `dir` resolve `playwright-core` through a symlink. `stop` is mandatory when the task ends — the profile holds live sessions.

For an automation browser already exposing a **local CDP endpoint**, attach without changing its context:

```sh
bun scripts/browser-sign-in-playwright.ts http://127.0.0.1:9222 'Research browser'
```

**Known issue (2026-09-21):** that command hangs under Bun — `playwright-core` 1.63's `connectOverCDP` never resolves there, while Node connects in ~45 ms. Node cannot run the `.ts` directly (parameter properties in `src/browser-sign-in.ts`), so bundle first: `bun build scripts/browser-sign-in-playwright.ts --target=node --format=esm --external playwright-core --outfile bridge.mjs`, then `node bridge.mjs <cdp> <name>` from a directory whose `node_modules` contains `playwright-core`. The launcher above does exactly this.

With multiple contexts, supply the intended index as the fourth argument after the LFG URL. This command does not launch Chrome or enable a debug port. Do not use it to attach your default personal Chrome; use the extension there. A browser that exposes neither a context nor CDP needs integration in its owning process; the bridge does not discover arbitrary Playwright processes automatically.

## Boundaries

- Cookies are credentials. Transfers use HTTPS off-loopback, reject redirects, have no extra on-disk cookie bundle, and bypass agent transcripts, journals, shared URL caches and logs.
- Each target has one in-flight transfer, bounded to 128 cookies / 256 KiB with a 15-second deadline. No offline queue or retry/replay. Timeout/disconnect means **unknown delivery**, not failure to write; inspect the browser before retrying.
- The iOS website store is nonpersistent and discarded on dismissal/completion. Background snapshots hide the login view; returning from a password manager or 2FA app can continue the login.
- Session/expiry, domain/host-only, path, Secure, HttpOnly and available SameSite metadata are preserved. WKWebView's cookie export is not a full browser-state export. Partitioned cookie state, localStorage, IndexedDB and device-bound session keys are unsupported.
- Google embedded OAuth is not supported. There is no user-agent spoofing. Sign in directly on your Mac for unsupported sign-in providers. Browser Stream is currently hidden in the iOS app.
- HTTP is allowed only for localhost development. Production phone connections should use the existing Cloudflare Access HTTPS host. The adapter socket separately requires the local setup token; no token is sent in a URL.

## Verification

```sh
bunx playwright-core install chromium
bun test src/browser-sign-in.test.ts src/browser-sign-in.integration.test.ts
swift test --package-path ios/LFGCore --filter PhoneSignIn
```

The integration tests use an isolated Chromium profile and synthetic credentials. Their test-only extension manifest pregrants `portal.example.com`; production permission requests still require user consent. Tests check a protected page, HttpOnly/Secure/session attributes, wrong-target isolation and unapproved-site rejection.

For the complete phone UI fixture, run `bun scripts/browser-sign-in-fixture.ts`, point a simulator build at `http://127.0.0.1:9982`, then sign into `http://127.0.0.1:9982/fixture/login` using any **synthetic** email/password. `/fixture/status` confirms whether the real destination Playwright context received the cookie. The fixture checks port availability, uses no database or production LFG endpoints, and closes its own browser on Ctrl-C.
