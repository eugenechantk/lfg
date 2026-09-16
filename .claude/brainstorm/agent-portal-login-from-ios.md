# Signing an agent into a portal from the iOS client

**Date:** 2026-09-06
**Status:** brainstorm / feasibility — nothing implemented
**Prompt:** Sessions on the host sometimes hit a login wall on a portal, and Eugene is not at the host. Can the iOS client do what https://x.com/anshnanda/status/2094576662033715545 describes?

## The method in the tweet

Ansh Nanda's explanation of Ronith's (@ronithhh) product:

1. The phone opens a webview on the site the agent needs.
2. The user logs in there. The password manager works because auth happens on the device. The site sets cookies in the webview.
3. The cookies are shipped to the agent's machine.
4. The agent's browser now carries the session. The password never touches the agent, the chat, or the logs.

Open question he raises: encryption at rest and in transit.

## Verdict

Yes, and lfg already has most of the seams. It is a ~3-piece feature:

| Piece | Where | Effort |
| --- | --- | --- |
| Capture: in-app `WKWebView` login sheet, read the cookie jar on completion | `ios/LFG` | small |
| Transport: `POST /api/sessions/:id/browser-cookies` (mirrors `upload`) | `src/commands/serve.ts` + `LFGClient.swift` | small |
| Inject into the agent's browser on the host | new `src/browser-cookies.ts` | depends on which browser (below) |

The hard part is not the phone or the wire. It is **which browser on the host receives the cookies**. Sessions use two:

### Target A — gstack `browse` (headless Chromium via Playwright) — trivial

The `browse` skill already has `browse cookie-import <json-file>` (`~/.claude/skills/browse/src/write-commands.ts:645`). It takes a JSON array of cookies, fills the domain from the current page if missing, and the session's persistent context keeps them. So for this target the host side is: write the array to `~/.lfg/cookies/<domain>-<ts>.json` (must be under one of the skill's `SAFE_DIRECTORIES`; check `~/.lfg` qualifies or use the session cwd), and tell the agent the path. Nothing else to build.

### Target B — `claude-in-chrome` (Eugene's real Chrome 152, Default profile) — needs a helper

Two things block a direct write:

- Chrome ≥136 refuses `--remote-debugging-port` on the default user-data-dir, so lfg cannot CDP `Network.setCookie` into the running browser.
- The on-disk `Cookies` SQLite is encrypted with a Keychain-held key. Writing it directly is fragile and races the running browser.

Two workable routes:

1. **Tiny lfg helper extension in the Default profile.** Manifest with `cookies` + host permission for `http://127.0.0.1:8766/*`. It polls `/api/browser-cookies/pending` (localhost, no auth needed — same posture as the rest of the API) and calls `chrome.cookies.set` for each, which supports `httpOnly` and `secure`. Works with the live browser, no relaunch, no CDP, and claude-in-chrome sees the session immediately. **Recommended for B.**
2. **A dedicated "agent" Chrome profile** launched by lfg with `--user-data-dir=~/.lfg/chrome --remote-debugging-port=<port>`, claude-in-chrome extension installed there. lfg injects over CDP. Cleaner isolation from Eugene's personal browsing, but the claude-in-chrome extension must be paired to that profile and the login session of claude.ai lives there too. More moving parts; do this only if profile isolation becomes a requirement.

## Flow, end to end

1. Agent hits a login wall. It says so in the transcript with the URL, ideally via `AskUserQuestion` ("I need you to sign in to https://portal.example.com"). The client already renders the live prompt (`PromptPanelView`), and `/api/term/scan` already detects URLs on the pane for tappable chips.
2. Client shows **Sign in for this agent** next to the URL (prompt panel, or long-press on a link chip, or a menu action on the session where the user pastes a URL).
3. A sheet opens a `WKWebView` with a **non-persistent** `WKWebsiteDataStore` (fresh jar per login; nothing lingers on the phone). Set `customUserAgent` to a desktop Chrome UA so the site issues a desktop session and doesn't bind it to a mobile fingerprint.
4. User logs in with Face ID + password manager as usual. A **Done** button (plus an optional auto-detect: URL leaves the login origin, or a configurable "logged-in" URL prefix) ends the flow.
5. Client reads `webView.configuration.websiteDataStore.httpCookieStore.allCookies()` — this returns `HttpOnly` cookies too — filters to the target registrable domain (plus SSO domains the user opted into, see gaps), optionally reads `localStorage` for the origin via `evaluateJavaScript`, and POSTs `{domain, url, cookies[], localStorage?}`.
6. Server stores the bundle under `~/.lfg/cookies/` with mode 600, writes the browse-format JSON, queues it for the Chrome helper, and drops a line into the session (via `sendq`) like: "Cookies for portal.example.com are installed in browse and Chrome; retry the page." The agent continues.
7. Client destroys the data store.

## Security posture

- **In transit:** Cloudflare tunnel + Access, TLS edge to host. Same as the attachments upload today. Adequate.
- **At rest on host:** the cookies end up in the browser profile regardless — that is the point. The extra copy under `~/.lfg/cookies/` should be deleted after injection, or kept encrypted-at-rest only if we want re-injection later. Default: delete after both targets confirm.
- **On the phone:** non-persistent data store, discarded after send. No cookies persist in the app.
- **Never log cookie values.** `sendq.log` and `lfg-serve.log` get domain + count only.
- **Blast radius:** anyone who can reach the lfg API can push cookies into Eugene's Chrome. Today that is Access-gated, and the API is already able to type into his terminals, so this is not a new trust level. Still, the helper extension should only accept cookies for domains the phone explicitly named, and should reject `.google.com`-style broad domains unless the user confirmed SSO scope.

## Gaps and traps

- **Session bound to IP/UA.** Cloudflare `cf_clearance`, some banks, and some SSO providers bind the session to user agent and/or IP. UA is fixable (desktop UA in the webview). IP is not: the phone logs in from a different network than the host. Expect a re-challenge on those sites; most SaaS portals do not do this.
- **Google / Microsoft OAuth in embedded webviews.** Google returns `disallowed_useragent` for `WKWebView` logins. Desktop UA spoof usually gets past it, but it is not guaranteed. Fallback: `ASWebAuthenticationSession` shares Safari cookies but does **not** let us read them, so it is not an option. If Google SSO matters, the webview path is the only one.
- **Token in localStorage, not cookies.** SPAs that keep a JWT in localStorage need the localStorage capture (step 5). The tweet's method has the same hole.
- **Same-domain SSO chains.** Login at `portal.example.com` may set cookies on `auth.example.com` and `sso.corp.com`. Capture everything in the jar and let the user tick the domains in a small list before sending, defaulting to the target's registrable domain.
- **Cookie expiry.** Session cookies without `expires` are fine for `chrome.cookies.set` and Playwright, but note them so the agent knows they die when the browser restarts.
- **Codex sessions.** Same host browsers, same fix. Nothing codex-specific.

## Recommendation

Build it in this order, product tier when we do:

1. **Target A + the iOS sheet + the endpoint.** Ships the whole user-visible flow, and the agent can use `browse` for any logged-in portal work immediately.
2. **Helper extension for Chrome** so claude-in-chrome sessions benefit too.
3. Later: localStorage capture and the SSO-domain picker, once a real portal needs them.

Not worth doing: the dedicated agent Chrome profile (route B2), unless isolation from Eugene's personal Chrome becomes a requirement.

## Open decisions for Eugene

- Which portals are the actual cases? If they are all reachable by `browse`, step 2 can wait.
- Should cookies persist on the host for re-injection after a browser restart, or be one-shot? Default proposed: one-shot, delete after inject.
