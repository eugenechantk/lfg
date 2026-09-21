# Streaming a VPS-hosted Chrome to the LFG iOS app

Date: 2026-09-21
Status: feasibility note from reading the repo. Nothing built, run, or measured except one `tailscale ping`.

## Question

If Chrome runs in a container on the Hostinger VPS (`linuxserver/chromium`-style image with a
built-in web viewer), can the LFG iOS app show it live and let Eugene tap and type into it?

## What LFG has today

| Piece | What it does | Live? | Input? |
| --- | --- | --- | --- |
| `BrowserPreviewCard.swift` + `src/browser-preview.ts` | Shows the latest screenshot an agent's browser tool emitted. The source comment says it is deliberately not labelled "Live". | No | No |
| `PhoneSignInView.swift` + `src/browser-sign-in.ts` | Logs in inside a local `WKWebView` on the phone, then transfers the cookies to the remote browser. | n/a, nothing is streamed | Local only |
| `.codex/brainstorm/browser-takeover-from-ios.md` | Plan for live takeover of a Chrome window on a Mac: ScreenCaptureKit capture, CGEvent input, lease/handoff. | Not built | Not built |

So the app cannot do it as shipped. It does already embed `WKWebView`, which is the only client piece needed.

## Why the VPS case is easier than the Mac case

The takeover brainstorm is hard because the browser lives on a Mac desktop: it needs a native
capture helper, Screen Recording and Accessibility permissions, window picking, foregrounding,
and coordinate mapping through Retina scale. It says cloud browsers "require their own
capture/input adapter" and names noVNC-in-WKWebView as the fast prototype.

A container image with a web viewer is that adapter, prebuilt. The container owns its whole
virtual display, so there is no window to pick, no permission prompt, and nobody else's
foreground to steal. The viewer page already does video, touch-to-pointer mapping, scroll, and
an on-screen keyboard toggle.

## Path A: WKWebView pointed at the container's viewer (prototype)

- New full-screen view in the iOS app that loads the viewer URL.
- Reachability, pick one:
  1. Phone on the tailnet, viewer bound to `tailscale0` on the VPS. Least code. Needs a firewall
     rule on the VPS; today nothing answers on its tailnet address.
  2. LFG host proxies HTTP + WebSocket to the VPS, reusing existing host auth. Works without
     Tailscale on the phone, costs an extra hop.
- Latency: `tailscale ping` from the Air to the VPS was 64 ms via DERP(sin), 75 ms direct.
  Frame encode and decode add to that; expect usable for login and clicking, not smooth video.
- Known rough edges: typing through a canvas viewer on iOS (no autofill, no password manager,
  IME quirks), pinch-zoom fighting the viewer's own gestures, the viewer's desktop-oriented
  control bar on a phone screen.

## Path B: CDP screencast with a native SwiftUI viewer (if A proves the value)

Because we own this Chrome, we can attach to its remote-debugging port:
`Page.startScreencast` for JPEG frames, `Input.dispatchTouchEvent` / `insertText` for input.
Per-tab, works headless, no desktop or VNC layer, and frames fit the existing `BrowserFrame`
plumbing. The brainstorm's worry about a second debugger attaching to a vendor-controlled Chrome
does not apply to a browser we launch ourselves, but coexistence with the agent's own CDP
client still needs a test.

## Still required either way

The control contract from the takeover brainstorm carries over unchanged: hold the agent,
confirm it is quiet, exclusive lease, explicit "Return to agent", disconnect means held, keep
takeover frames out of logs and transcript history. Streaming is the easy half; safe handoff is
the real work.

## Caveat that may outweigh all of this

The VPS has a datacenter IP. Google, Meta and Cloudflare-protected sites challenge or block
those far more than a home connection. A streamed browser on the VPS is a good fit for QA,
scraping and low-defence sites, and a poor fit for ad accounts and Google logins. The Pro at
home remains the better host for those, which is the case the ScreenCaptureKit plan covers.

## Recommendation

Do Path A as a throwaway spike once the Air can log in to the VPS: start the container, open the
viewer in Safari on the iPhone over Tailscale first (zero app code), and judge typing and
latency by hand. Only wire a `WKWebView` screen into LFG if that feels usable.
