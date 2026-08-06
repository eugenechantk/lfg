import { describe, expect, test } from "bun:test";
import {
  BrowserFrameExtractor,
  BrowserFrameStore,
  publishBrowserFrame,
} from "./browser-preview.ts";

const jpegBase64 = Buffer.from([0xff, 0xd8, 0xff, 0xd9]).toString("base64");

describe("BrowserFrameExtractor", () => {
  test("accepts a Claude in Chrome screenshot tool result", () => {
    const extractor = new BrowserFrameExtractor();
    extractor.consume(JSON.stringify({
      type: "assistant",
      message: { content: [{
        type: "tool_use",
        id: "tool-1",
        name: "mcp__claude-in-chrome__computer",
        input: { action: "screenshot", tabId: 42 },
      }] },
    }));

    const frame = extractor.consume(JSON.stringify({
      type: "user",
      message: { content: [{
        type: "tool_result",
        tool_use_id: "tool-1",
        content: [{
          type: "image",
          source: { type: "base64", media_type: "image/jpeg", data: jpegBase64 },
        }],
      }] },
    }));

    expect(frame?.source).toBe("claude");
    expect(frame?.contentType).toBe("image/jpeg");
    expect([...frame!.data]).toEqual([0xff, 0xd8, 0xff, 0xd9]);
  });

  test("accepts a Claude browser_batch that contains a screenshot action", () => {
    const extractor = new BrowserFrameExtractor();
    extractor.consume(JSON.stringify({
      message: { content: [{
        type: "tool_use",
        id: "tool-batch",
        name: "mcp__claude-in-chrome__browser_batch",
        input: { actions: [{ action: "wait" }, { action: "screenshot" }] },
      }] },
    }));

    const frame = extractor.consume(JSON.stringify({
      message: { content: [{
        type: "tool_result",
        tool_use_id: "tool-batch",
        content: [{ type: "image", data: jpegBase64, mimeType: "image/jpeg" }],
      }] },
    }));

    expect(frame?.source).toBe("claude");
  });

  test("accepts a Codex custom tool output input_image data URL", () => {
    const extractor = new BrowserFrameExtractor();
    extractor.consume(JSON.stringify({
      type: "response_item",
      payload: {
        type: "custom_tool_call",
        call_id: "call-browser",
        name: "exec",
        input: "await tools.mcp__node_repl__js({ code: `await chrome.tabs.selected(); await tab.screenshot()` })",
      },
    }));
    const frame = extractor.consume(JSON.stringify({
      type: "response_item",
      payload: {
        type: "custom_tool_call_output",
        call_id: "call-browser",
        output: [{
          type: "input_image",
          image_url: `data:image/jpeg;base64,${jpegBase64}`,
        }],
      },
    }));

    expect(frame?.source).toBe("codex");
    expect(frame?.contentType).toBe("image/jpeg");
  });

  test("ignores Codex images from non-browser tools", () => {
    const extractor = new BrowserFrameExtractor();
    extractor.consume(JSON.stringify({
      type: "custom_tool_call",
      call_id: "call-view-image",
      name: "exec",
      input: "await tools.view_image({ path: '/tmp/simulator.jpg' })",
    }));
    const frame = extractor.consume(JSON.stringify({
      type: "custom_tool_call_output",
      call_id: "call-view-image",
      output: [{
        type: "input_image",
        image_url: `data:image/jpeg;base64,${jpegBase64}`,
      }],
    }));
    expect(frame).toBeNull();
  });

  test("ignores unrelated user-uploaded images", () => {
    const extractor = new BrowserFrameExtractor();
    const frame = extractor.consume(JSON.stringify({
      type: "user",
      message: { content: [{
        type: "image",
        source: { type: "base64", media_type: "image/jpeg", data: jpegBase64 },
      }] },
    }));
    expect(frame).toBeNull();
  });
});

describe("BrowserFrameStore", () => {
  test("keeps bytes out of the journal and serves only the latest frame", async () => {
    const store = new BrowserFrameStore();
    const events: unknown[] = [];
    const journal = {
      append(sid: string, type: string, payload: unknown) {
        events.push({ sid, type, payload });
        return events.length;
      },
    };

    const meta = publishBrowserFrame(journal, store, "session-1", {
      data: Uint8Array.from([1, 2, 3]),
      contentType: "image/jpeg",
      source: "prototype",
    });

    expect(meta?.sessionId).toBe("session-1");
    expect(JSON.stringify(events)).not.toContain("AQID");
    expect(events).toEqual([{ sid: "session-1", type: "browser_frame", payload: meta }]);

    const response = store.response("session-1", meta!.frameId);
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("image/jpeg");
    expect([...new Uint8Array(await response.arrayBuffer())]).toEqual([1, 2, 3]);

    const metadata = await store.metadataResponse("session-1").json();
    expect(metadata).toEqual(meta);
    expect(JSON.stringify(metadata)).not.toContain("AQID");
  });

  test("deduplicates an identical frame", () => {
    const store = new BrowserFrameStore();
    const candidate = {
      data: Uint8Array.from([1, 2, 3]),
      contentType: "image/jpeg",
      source: "prototype" as const,
    };
    expect(store.publish("session-1", candidate)).not.toBeNull();
    expect(store.publish("session-1", candidate)).toBeNull();
  });
});
