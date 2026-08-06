import { createHash } from "node:crypto";
import type { Journal } from "./journal.ts";

export type BrowserFrameSource = "claude" | "codex" | "prototype";

export type BrowserFrameCandidate = {
  data: Uint8Array;
  contentType: string;
  source: BrowserFrameSource;
  capturedAt?: number;
};

export type BrowserFrameMeta = {
  sessionId: string;
  frameId: string;
  capturedAt: number;
  contentType: string;
  source: BrowserFrameSource;
};

type StoredFrame = BrowserFrameMeta & {
  data: Uint8Array;
  digest: string;
};

const MAX_FRAME_BYTES = 6 * 1024 * 1024;
const SUPPORTED_IMAGE_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);

function object(value: unknown): Record<string, unknown> | null {
  return value != null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function visit(value: unknown, fn: (value: Record<string, unknown>) => void): void {
  if (Array.isArray(value)) {
    for (const child of value) visit(child, fn);
    return;
  }
  const row = object(value);
  if (!row) return;
  fn(row);
  for (const child of Object.values(row)) visit(child, fn);
}

function decodeBase64(data: string): Uint8Array | null {
  try {
    const bytes = Uint8Array.from(Buffer.from(data, "base64"));
    if (!bytes.length || bytes.length > MAX_FRAME_BYTES) return null;
    return bytes;
  } catch {
    return null;
  }
}

function imageIn(value: unknown): { data: Uint8Array; contentType: string } | null {
  let found: { data: Uint8Array; contentType: string } | null = null;
  visit(value, (row) => {
    if (found) return;

    const imageURL = typeof row.image_url === "string" ? row.image_url : null;
    const dataURL = imageURL?.match(/^data:(image\/(?:jpeg|png|webp));base64,(.+)$/s);
    if (dataURL) {
      const data = decodeBase64(dataURL[2]);
      if (data) found = { data, contentType: dataURL[1] };
      return;
    }

    const source = object(row.source);
    const raw = typeof source?.data === "string"
      ? source.data
      : typeof row.data === "string"
        ? row.data
        : null;
    const contentType = typeof source?.media_type === "string"
      ? source.media_type
      : typeof row.mimeType === "string"
        ? row.mimeType
        : typeof row.media_type === "string"
          ? row.media_type
          : null;
    if (!raw || !contentType || !SUPPORTED_IMAGE_TYPES.has(contentType)) return;
    const data = decodeBase64(raw);
    if (data) found = { data, contentType };
  });
  return found;
}

function isClaudeBrowserScreenshot(row: Record<string, unknown>): boolean {
  if (row.type !== "tool_use" || typeof row.name !== "string") return false;
  if (!row.name.includes("claude-in-chrome")) return false;
  return JSON.stringify(row.input ?? {}).toLowerCase().includes("screenshot");
}

/**
 * Stateful per-transcript adapter. Claude tool results identify the preceding
 * tool_use by id, so the adapter remembers only screenshot-producing tool ids.
 * Codex browser output is self-describing as a custom_tool_call_output image.
 */
export class BrowserFrameExtractor {
  private claudeScreenshotToolIds = new Set<string>();
  private codexBrowserCallIds = new Set<string>();

  consume(line: string): BrowserFrameCandidate | null {
    let root: unknown;
    try {
      root = JSON.parse(line);
    } catch {
      return null;
    }

    visit(root, (row) => {
      if (isClaudeBrowserScreenshot(row) && typeof row.id === "string") {
        this.claudeScreenshotToolIds.add(row.id);
      }
      if (row.type === "custom_tool_call" && typeof row.call_id === "string") {
        const name = typeof row.name === "string" ? row.name.toLowerCase() : "";
        const input = typeof row.input === "string" ? row.input.toLowerCase() : "";
        const directBrowserTool = name.includes("chrome") || name.includes("browser");
        const chromePluginCall = input.includes("mcp__node_repl__js")
          && (input.includes("chrome.") || input.includes("browser.") || input.includes("screenshot"));
        if (directBrowserTool || chromePluginCall) this.codexBrowserCallIds.add(row.call_id);
      }
    });

    const claudeImages: Array<{ data: Uint8Array; contentType: string }> = [];
    visit(root, (row) => {
      if (row.type !== "tool_result") return;
      if (typeof row.tool_use_id !== "string" || !this.claudeScreenshotToolIds.has(row.tool_use_id)) return;
      const image = imageIn(row.content);
      if (image) claudeImages.push(image);
      this.claudeScreenshotToolIds.delete(row.tool_use_id);
    });
    const claudeImage = claudeImages.at(-1);
    if (claudeImage) return { ...claudeImage, source: "claude" };

    const codexImages: Array<{ data: Uint8Array; contentType: string }> = [];
    visit(root, (row) => {
      if (row.type !== "custom_tool_call_output") return;
      if (typeof row.call_id !== "string" || !this.codexBrowserCallIds.has(row.call_id)) return;
      const image = imageIn(row);
      if (image) codexImages.push(image);
      this.codexBrowserCallIds.delete(row.call_id);
    });
    const codexImage = codexImages.at(-1);
    return codexImage ? { ...codexImage, source: "codex" } : null;
  }
}

/** Latest-only, process-local image store. Frame bytes are intentionally not
 * written to the cursor journal; only BrowserFrameMeta is journaled. */
export class BrowserFrameStore {
  private latest = new Map<string, StoredFrame>();

  publish(sessionId: string, candidate: BrowserFrameCandidate): BrowserFrameMeta | null {
    if (!sessionId || !candidate.data.length || candidate.data.length > MAX_FRAME_BYTES) return null;
    if (!SUPPORTED_IMAGE_TYPES.has(candidate.contentType)) return null;
    const digest = createHash("sha256").update(candidate.data).digest("hex");
    if (this.latest.get(sessionId)?.digest === digest) return null;
    const meta: BrowserFrameMeta = {
      sessionId,
      frameId: digest.slice(0, 20),
      capturedAt: candidate.capturedAt ?? Date.now(),
      contentType: candidate.contentType,
      source: candidate.source,
    };
    this.latest.set(sessionId, { ...meta, data: candidate.data, digest });
    return meta;
  }

  metadata(sessionId: string): BrowserFrameMeta | null {
    const frame = this.latest.get(sessionId);
    if (!frame) return null;
    const { data: _, digest: __, ...meta } = frame;
    return meta;
  }

  metadataResponse(sessionId: string): Response {
    const meta = this.metadata(sessionId);
    return meta
      ? new Response(JSON.stringify(meta), { headers: { "Content-Type": "application/json" } })
      : new Response(JSON.stringify({ error: "browser frame not found" }), {
          status: 404,
          headers: { "Content-Type": "application/json" },
        });
  }

  response(sessionId: string, frameId?: string | null): Response {
    const frame = this.latest.get(sessionId);
    if (!frame || (frameId && frame.frameId !== frameId)) {
      return new Response(JSON.stringify({ error: "browser frame not found" }), {
        status: 404,
        headers: { "Content-Type": "application/json" },
      });
    }
    return new Response(frame.data, {
      headers: {
        "Content-Type": frame.contentType,
        "Content-Length": String(frame.data.length),
        "Cache-Control": "no-store",
        "X-LFG-Frame-Id": frame.frameId,
        "X-LFG-Captured-At": String(frame.capturedAt),
      },
    });
  }
}

export function publishBrowserFrame(
  journal: Pick<Journal, "append">,
  store: BrowserFrameStore,
  sessionId: string,
  candidate: BrowserFrameCandidate,
): BrowserFrameMeta | null {
  const meta = store.publish(sessionId, candidate);
  if (meta) journal.append(sessionId, "browser_frame", meta);
  return meta;
}
