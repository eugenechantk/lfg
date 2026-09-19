// Transparent proxy to the real lfg server that behaves like Cloudflare Access:
// any request without the service-token headers is refused with 403 (the
// cookie alone is refused too, matching the real edge). Everything else is
// forwarded byte-for-byte, Range and all. Lets the simulator app exercise the
// header-injection seam (StreamingResourceLoader, resourceData) against real
// endpoints without the 50 KB/s tunnel in the way.
//
//   bun .claude/feature/evidence/media-fast-path/access-gate-stub.ts [port]
//   host URL in the app: http://127.0.0.1:<port>, credential id/secret below.
const port = Number(process.argv[2] ?? 8797);
const upstream = "http://127.0.0.1:8766";
const CLIENT_ID = "stub-client-id.access";
const CLIENT_SECRET = "stub-client-secret";
let n = 0;

Bun.serve({
  port,
  hostname: "127.0.0.1",
  idleTimeout: 255,
  async fetch(req) {
    const id = ++n;
    const url = new URL(req.url);
    const authed =
      req.headers.get("cf-access-client-id") === CLIENT_ID &&
      req.headers.get("cf-access-client-secret") === CLIENT_SECRET;
    const range = req.headers.get("range");
    if (!authed) {
      console.log(JSON.stringify({ id, t: new Date().toISOString(), status: 403, method: req.method, path: url.pathname + url.search, range }));
      return new Response("forbidden (no Access service token)", { status: 403 });
    }
    const headers = new Headers(req.headers);
    headers.delete("cf-access-client-id");
    headers.delete("cf-access-client-secret");
    headers.set("host", "127.0.0.1:8766");
    // fetch() transparently gunzips; forwarding the upstream's
    // `content-encoding: gzip` with an already-inflated body would make the
    // app's decoder fail ("cannot decode raw data"). Ask for identity instead.
    headers.set("accept-encoding", "identity");
    const res = await fetch(upstream + url.pathname + url.search, {
      method: req.method,
      headers,
      body: req.method === "GET" || req.method === "HEAD" ? undefined : req.body,
      redirect: "manual",
      // @ts-expect-error bun option
      duplex: "half",
    });
    console.log(JSON.stringify({
      id, t: new Date().toISOString(), status: res.status, method: req.method,
      path: url.pathname + url.search, range,
      contentRange: res.headers.get("content-range"), type: res.headers.get("content-type"),
      etag: res.headers.get("etag"), cache: res.headers.get("cache-control"),
    }));
    const out = new Headers(res.headers);
    out.delete("content-encoding");
    out.delete("content-length"); // body may have been re-framed; let Bun chunk it
    return new Response(res.body, { status: res.status, headers: out });
  },
});
console.log(`access-gate stub on http://127.0.0.1:${port} → ${upstream}`);
