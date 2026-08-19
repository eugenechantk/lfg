# Cloudflare multi-Mac access

## User story

As Eugene, I want Pro and Air to expose LFG and SSH through stable,
Access-protected Cloudflare hostnames so either Mac can browse and open the
other Mac's sessions without Tailscale, public IP stability, or router changes.

## Topology

| Mac | LFG API | SSH |
| --- | --- | --- |
| Pro | `lfg-pro.eugenechantk.me` → `127.0.0.1:8766` | `ssh-pro.eugenechantk.me` → `127.0.0.1:22` |
| Air | `lfg-air.eugenechantk.me` → `127.0.0.1:8766` | `ssh-air.eugenechantk.me` → `127.0.0.1:22` |

Both tunnels originate outbound from their Mac and remain compatible with the
Mac's Surfshark connection. Cloudflare Access protects every public hostname.

## Desktop profiles

- Pro's desktop reads Pro locally and Air through `lfg-air`; Air attaches with
  SSH alias `air` and `transport: "ssh"`.
- Air's desktop reads Air locally and Pro through `lfg-pro`; Pro attaches with
  SSH alias `pro` and `transport: "ssh"`.
- Clicking a remote tmux-backed session runs plain `ssh -t <alias> … tmux
  attach-session …`. tmux keeps the session alive if the WebSocket transport
  reconnects.

## Success criteria

- [ ] SC1: Air runs LFG on TCP 8766 from the latest `main` revision.
- [ ] SC2: Air's named Cloudflare tunnel publishes protected API and SSH
  hostnames, starts at login, and is healthy.
- [ ] SC3: `ssh air` from Pro and `ssh pro` from Air use `cloudflared access ssh`
  rather than a Tailscale/LAN address.
- [ ] SC4: Each desktop config contains localhost plus the other Mac's
  Cloudflare API URL and SSH-only alias.
- [ ] SC5: The latest desktop build is installed on Air and its headless feature
  suite passes there.
- [ ] SC6: Pro can query Air's LFG API and execute a non-interactive SSH command
  through Cloudflare Access after authentication.
- [ ] SC7: Each Mac's desktop Keychain contains an Access credential for the
  other Mac's HTTPS origin; neither host JSON nor Git contains the secret.

## Security decisions

- Do not publish TCP 22 or 8766 through the router.
- Do not commit named-tunnel credentials, Access service tokens, or generated
  private resources.
- Prefer Keychain for desktop tokens. A headlessly provisioned Mac may use the
  mode-`0400` `~/.cloudflared/lfg-access-service-token.private.json` fallback,
  which is accepted only for its declared HTTPS origin.
- Create the Access application before publishing each hostname.
- Keep Mosh available for private/LAN profiles, but force SSH for Cloudflare
  profiles because the published SSH route does not carry Mosh UDP traffic.
