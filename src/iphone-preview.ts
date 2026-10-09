import { readdir, readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { accessConfigFromEnv, authorizeTunnelledRequest, cachedJwks, type AccessConfig, type JwksSource } from "./access-jwt.ts";

const MAX_FRAME = 8 * 1024 * 1024;
const profileID = /^(?:default|[a-zA-Z0-9][a-zA-Z0-9_-]{0,79})$/;
type Phone = { id: string; name: string; key: string };
type Worker = { base: string; token: string };
type Options = {
  root?: string;
  access?: AccessConfig | null;
  keys?: JwksSource;
  start?: (id: string) => Promise<void>;
};

function json(value: unknown, status = 200): Response {
  return Response.json(value, { status, headers: { "Cache-Control": "no-store" } });
}

/** Only the host reads the private worker credentials. Never accepts a proxy URL. */
export function iphonePreviewRoutes(options: Options = {}) {
  const root = options.root ?? join(homedir(), ".iphone-control");
  const access = options.access === undefined ? accessConfigFromEnv() : options.access;
  const keys = options.keys ?? cachedJwks();
  const pending = new Map<string, Promise<void>>();

  async function phones(): Promise<Phone[]> {
    const entries = await readdir(join(root, "devices"), { withFileTypes: true }).catch(() => []);
    const ids = entries.filter(e => e.isDirectory() && profileID.test(e.name) && e.name !== "default").map(e => e.name).sort();
    ids.push("default");
    const found: Phone[] = [];
    for (const id of ids) {
      try {
        const path = id === "default" ? join(root, "config.json") : join(root, "devices", id, "config.json");
        const config = JSON.parse(await readFile(path, "utf8"));
        if (typeof config.udid !== "string" || !config.udid) continue;
        const key = createHash("sha256").update(config.udid).digest("hex").slice(0, 24);
        if (!found.some(p => p.key === key)) found.push({ id, name: id === "default" ? "Default iPhone" : id, key });
      } catch { /* A missing or half-written local profile is not a configured phone. */ }
    }
    return found;
  }

  async function worker(phone: Phone): Promise<Worker> {
    const info = JSON.parse(await readFile(join(root, "by-device", phone.key, "preview.json"), "utf8"));
    const url = new URL(info.base);
    // A corrupt state file must not turn this route into an arbitrary HTTP proxy.
    if (url.protocol !== "http:" || url.hostname !== "127.0.0.1" || !url.port ||
        Number(url.port) < 1024 || Number(url.port) === 8766 || url.username || url.password ||
        url.pathname !== "/" || url.search || url.hash || typeof info.token !== "string" || !info.token) {
      throw Error("Invalid preview worker");
    }
    return { base: url.origin, token: info.token };
  }

  async function call(phone: Phone, path: string, method = "GET") {
    const info = await worker(phone);
    const url = new URL(path, info.base);
    url.searchParams.set("token", info.token);
    const response = await fetch(url, { method, redirect: "error", signal: AbortSignal.timeout(3000) });
    if (!response.ok) { await response.body?.cancel(); throw Error("Preview worker unavailable"); }
    return response;
  }

  const start = options.start ?? (async (id: string) => {
    const script = join(homedir(), ".codex", "skills", "iphone-control", "scripts", "phone.py");
    const proc = Bun.spawn([Bun.which("uv") ?? "/opt/homebrew/bin/uv", "run", "--script", "--quiet", script, "preview", "start"], {
      env: { ...process.env, IPHONE_CONTROL_ROOT: root, IPHONE_CONTROL_DEVICE: id === "default" ? "" : id },
      stdout: "ignore", stderr: "ignore",
    });
    const timer = setTimeout(() => proc.kill(), 35000);
    try { if (await proc.exited !== 0) throw Error("Preview could not start"); }
    finally { clearTimeout(timer); }
  });

  /** Serialize control changes per physical phone, including aliases and rapid toggles. */
  async function control(phone: Phone, enabled: boolean) {
    const previous = pending.get(phone.key) ?? Promise.resolve();
    const next = previous.catch(() => {}).then(async () => {
      if (enabled) await start(phone.id);
      try { await (await call(phone, enabled ? "/resume" : "/pause", "POST")).body?.cancel(); }
      catch (error) { if (enabled) throw error; /* An absent worker is already off. */ }
    });
    pending.set(phone.key, next);
    try { await next; }
    finally { if (pending.get(phone.key) === next) pending.delete(phone.key); }
  }

  return async (req: Request): Promise<Response> => {
    const auth = await authorizeTunnelledRequest(req, access, keys);
    if (!auth.ok) return json({ error: "iPhone preview requires Cloudflare Access authentication." }, 403);
    const url = new URL(req.url);
    const origin = req.headers.get("origin");
    if (origin && origin !== url.origin) return json({ error: "Cross-origin preview requests are not allowed." }, 403);
    if (url.pathname === "/api/iphone-preview/devices" && req.method === "GET") {
      return json({ devices: (await phones()).map(({ id, name }) => ({ id, name })) });
    }
    const match = /^\/api\/iphone-preview\/([^/]+)\/(frame|enabled)$/.exec(url.pathname);
    if (!match || !profileID.test(match[1]!)) return json({ error: "Unknown preview route." }, 404);
    const [, id, action] = match;
    if ((action === "frame" && req.method !== "GET") || (action === "enabled" && req.method !== "POST")) {
      return json({ error: "Method not allowed." }, 405);
    }
    const phone = (await phones()).find(p => p.id === id);
    if (!phone) return json({ error: "This iPhone is not configured on this host." }, 404);
    try {
      if (action === "enabled") {
        if (!req.headers.get("content-type")?.startsWith("application/json")) return json({ error: "JSON required." }, 415);
        const body = await req.json().catch(() => null);
        if (!body || typeof body !== "object" || !("enabled" in body) || typeof body.enabled !== "boolean") {
          return json({ error: "enabled must be a boolean." }, 400);
        }
        await control(phone, body.enabled);
        return json({ enabled: body.enabled });
      }
      const status = await (await call(phone, "/status")).json() as { paused?: boolean };
      if (status.paused !== false) return json({ error: "Preview is paused. Turn Live preview on again." }, 409);
      const frame = await call(phone, "/frame");
      if (frame.status === 204) return new Response(null, { status: 204, headers: { "Cache-Control": "no-store" } });
      if (!frame.headers.get("content-type")?.startsWith("image/jpeg")) { await frame.body?.cancel(); throw Error("Invalid frame"); }
      const reader = frame.body!.getReader();
      const chunks: Uint8Array[] = [];
      let length = 0;
      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          length += value.byteLength;
          if (length > MAX_FRAME) throw Error("Frame too large");
          chunks.push(value);
        }
      } finally { await reader.cancel(); }
      const data = Buffer.concat(chunks, length);
      if (data[0] !== 0xff || data[1] !== 0xd8 || data.at(-2) !== 0xff || data.at(-1) !== 0xd9) throw Error("Invalid JPEG");
      return new Response(data, { headers: { "Content-Type": "image/jpeg", "Cache-Control": "no-store" } });
    } catch {
      // No worker token, local paths, or upstream error bodies leave the host.
      return json({ error: "iPhone preview is unavailable. Connect the phone and start iphone-control on this Mac, then try again." }, 503);
    }
  };
}
