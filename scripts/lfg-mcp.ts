#!/usr/bin/env bun
// Runs the lfg MCP server (src/mcp-server.ts) on loopback, for the `lfg-mcp`
// Cloudflare tunnel to expose at https://lfg-mcp.eugenechantk.me/mcp.
//
// Auth lives at the edge: a Cloudflare Access app with Managed OAuth on that
// hostname. Every tunnelled request must still carry a Cf-Access-Jwt-Assertion
// for THAT app's audience (LFG_MCP_ACCESS_AUD), so a missing or broken Access
// policy fails closed instead of opening the Mac to the internet. Loopback
// requests (no cf-connecting-ip) pass, for local testing.
//
//   LFG_MCP_PORT            default 8791 (never 8766 — that's lfg itself)
//   LFG_MCP_ACCESS_AUD      the Access app's AUD tag; unset = refuse all tunnelled requests
//   LFG_ACCESS_TEAM_DOMAIN  shared with lfg (.env)
//   LFG_BASE                default http://127.0.0.1:8766
//   LFG_MCP_DOWNLOAD_BASE   default https://lfg-files.eugenechantk.me (download_file URLs)

import { homedir } from "node:os";
import { join } from "node:path";
import { cachedJwks, authorizeTunnelledRequest, accessConfigFromEnv } from "../src/access-jwt.ts";
import { createMcpHandler } from "../src/mcp-server.ts";
import { lfgTools, SERVER_INSTRUCTIONS } from "../src/mcp-lfg-tools.ts";
import { DownloadStore, handleDownload } from "../src/mcp-downloads.ts";
import { ensurePdfHelper } from "../src/pdf-extract.ts";

const port = Number(process.env.LFG_MCP_PORT ?? 8791);
if (port === 8766) throw new Error("port 8766 belongs to lfg serve");
const lfgBase = process.env.LFG_BASE ?? "http://127.0.0.1:8766";
const access = accessConfigFromEnv({
  LFG_ACCESS_TEAM_DOMAIN: process.env.LFG_ACCESS_TEAM_DOMAIN,
  LFG_ACCESS_AUD: process.env.LFG_MCP_ACCESS_AUD,
});
const keys = cachedJwks();
// download_file's expiring links, served at /dl/ on a separate, login-free
// hostname (the tunnel routes only ^/dl/ there; /mcp stays behind Access).
const downloads = new DownloadStore(join(homedir(), ".lfg", "lfg-mcp-downloads.json"));
const downloadBase = process.env.LFG_MCP_DOWNLOAD_BASE ?? "https://lfg-files.eugenechantk.me";

const log = (line: string) => console.log(`${new Date().toISOString()} lfg-mcp: ${line}`);

const mcp = createMcpHandler({
  name: "lfg",
  version: "0.2.0",
  instructions: SERVER_INSTRUCTIONS,
  tools: lfgTools({ base: lfgBase, downloads, downloadBase }),
  log,
});

Bun.serve({
  hostname: "127.0.0.1",
  port,
  async fetch(req) {
    const url = new URL(req.url);
    const via = req.headers.get("cf-connecting-ip") ? "tunnel" : "local";
    // Download links carry their own capability token and need no Access login.
    if (url.pathname.startsWith("/dl/")) return handleDownload(req, downloads, log) ?? new Response("not found", { status: 404 });
    if (url.pathname !== "/mcp") {
      log(`${req.method} ${url.pathname} ${via} → 404`);
      return new Response("not found", { status: 404 });
    }
    const auth = await authorizeTunnelledRequest(req, access, keys);
    if (!auth.ok) {
      log(`${req.method} /mcp ${via} → 401 (${auth.reason})`);
      return new Response("unauthorized", { status: 401 });
    }
    const res = await mcp(req);
    log(`${req.method} /mcp ${via} → ${res.status}`);
    return res;
  },
});

// Build the PDF reader now, not during a remote caller's first read_file.
ensurePdfHelper().then(
  (bin) => log(`pdf reader ready: ${bin}`),
  (e) => log(`pdf reader unavailable: ${(e as Error).message}`),
);

log(`listening on 127.0.0.1:${port}; lfg at ${lfgBase}; access ${access ? `aud ${access.aud.slice(0, 8)}…` : "NOT CONFIGURED (tunnel requests refused)"}`);
