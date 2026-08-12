// Latency-injecting reverse proxy → makes a LAN host look like a DERP relay.
// Verification rig for .claude/feature/rtt-adaptive-timeouts.md.
//   bun slowproxy.ts <listenPort> <upstream> <delayMs>
const [, , portArg, upstreamArg, delayArg] = Bun.argv;
const PORT = Number(portArg ?? 8777);
const UPSTREAM = upstreamArg ?? "http://127.0.0.1:8766";
const DELAY = Number(delayArg ?? 150);

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

console.log(`[slowproxy] :${PORT} -> ${UPSTREAM}  (+${DELAY}ms each way)`);

Bun.serve({
  port: PORT,
  idleTimeout: 0,
  async fetch(req) {
    const url = new URL(req.url);
    const target = UPSTREAM + url.pathname + url.search;
    // Outbound leg.
    await sleep(DELAY);
    let upstream: Response;
    try {
      upstream = await fetch(target, {
        method: req.method,
        headers: req.headers,
        body: req.body,
        // @ts-expect-error bun accepts duplex for streaming bodies
        duplex: "half",
      });
    } catch (e) {
      console.log(`[slowproxy] upstream error ${url.pathname}: ${e}`);
      return new Response("upstream error", { status: 502 });
    }
    // Return leg. SSE bodies stream through untouched — only the head is
    // delayed, which is exactly the shape of a relayed connection.
    await sleep(DELAY);
    console.log(`[slowproxy] ${req.method} ${url.pathname} -> ${upstream.status}`);
    return new Response(upstream.body, {
      status: upstream.status,
      headers: upstream.headers,
    });
  },
});
