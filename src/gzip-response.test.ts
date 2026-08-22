import { describe, expect, test } from "bun:test";
import { compressJsonResponse } from "./commands/serve.ts";

const bigBody = JSON.stringify({ messages: Array(200).fill("a".repeat(64)) });

function jsonResponse(body: string): Response {
  return new Response(body, { headers: { "Content-Type": "application/json" } });
}

function request(acceptEncoding?: string): Request {
  return new Request("http://localhost/api/sessions", {
    headers: acceptEncoding ? { "Accept-Encoding": acceptEncoding } : {},
  });
}

describe("compressJsonResponse — bug 009 follow-up: nothing on the phone path compresses", () => {
  test("gzips a large JSON body for a gzip-accepting client", async () => {
    const res = await compressJsonResponse(request("gzip, deflate, br"), jsonResponse(bigBody));

    expect(res.headers.get("content-encoding")).toBe("gzip");
    expect(res.headers.get("vary")).toBe("Accept-Encoding");
    const wire = new Uint8Array(await res.arrayBuffer());
    expect(wire.byteLength).toBeLessThan(bigBody.length / 2);
    expect(new TextDecoder().decode(Bun.gunzipSync(wire))).toBe(bigBody);
  });

  test("a client without Accept-Encoding gets identity bytes (plain curl, the CLI)", async () => {
    const res = await compressJsonResponse(request(), jsonResponse(bigBody));

    expect(res.headers.get("content-encoding")).toBeNull();
    expect(await res.text()).toBe(bigBody);
  });

  test("small bodies are not worth the header overhead", async () => {
    const res = await compressJsonResponse(request("gzip"), jsonResponse(`{"ok":true}`));

    expect(res.headers.get("content-encoding")).toBeNull();
    expect(await res.text()).toBe(`{"ok":true}`);
  });

  test("non-JSON responses pass through untouched (SSE, files, frames)", async () => {
    const sse = new Response("data: x\n\n", {
      headers: { "Content-Type": "text/event-stream" },
    });

    const res = await compressJsonResponse(request("gzip"), sse);

    expect(res).toBe(sse);
    expect(res.headers.get("content-encoding")).toBeNull();
  });
});
