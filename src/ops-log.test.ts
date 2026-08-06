// The log exists so the NEXT "Stop doesn't work" report arrives with evidence.
// Its one hard requirement is that it can never break the op it describes.
import { describe, expect, test, beforeEach } from "bun:test";
import { mkdtempSync, readFileSync, writeFileSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { logOp } from "./ops-log.ts";

const dir = mkdtempSync(join(tmpdir(), "ops-log-"));
let n = 0;
let path = "";

beforeEach(() => {
  path = join(dir, `ops${n++}.log`);
  process.env.LFG_OPS_LOG = path;
});

const lines = () =>
  readFileSync(path, "utf8")
    .trim()
    .split("\n")
    .map((l) => JSON.parse(l));

describe("logOp", () => {
  test("writes one JSON object per op with a timestamp", async () => {
    await logOp({ op: "close", sessionId: "s1", ok: true, ms: 12, panes: 2 });
    const [row] = lines();
    expect(row.op).toBe("close");
    expect(row.ok).toBe(true);
    expect(row.panes).toBe(2);
    expect(Date.parse(row.at)).toBeGreaterThan(0);
  });

  test("appends rather than truncating — history is the point", async () => {
    await logOp({ op: "close", sessionId: "a", ok: true, ms: 1 });
    await logOp({ op: "interrupt", sessionId: "b", ok: false, ms: 2 });
    expect(lines().map((r) => r.sessionId)).toEqual(["a", "b"]);
  });

  // The failures are the rows that matter. `sendq`'s pruning erased exactly these
  // and left "100% delivered" as the only visible history.
  test("a FAILED op is recorded, not dropped", async () => {
    await logOp({
      op: "interrupt",
      sessionId: "wedged",
      ok: false,
      ms: 1500,
      stopped: false,
      target: "cy-001114:0.0",
    });
    const [row] = lines();
    expect(row.ok).toBe(false);
    expect(row.stopped).toBe(false);
    expect(row.target).toBe("cy-001114:0.0");
  });

  test("creates the directory when data/ doesn't exist yet", async () => {
    path = join(dir, "nested", "deeper", "ops.log");
    process.env.LFG_OPS_LOG = path;
    await logOp({ op: "close", sessionId: "s", ok: true, ms: 1 });
    expect(existsSync(path)).toBe(true);
  });

  test("rotates once past the size cap, keeping the previous file", async () => {
    writeFileSync(path, "x".repeat(5 * 1024 * 1024 + 1));
    await logOp({ op: "close", sessionId: "fresh", ok: true, ms: 1 });
    expect(existsSync(`${path}.1`)).toBe(true);
    expect(lines()).toHaveLength(1); // new file holds only the new row
  });

  // THE invariant: logging is best-effort and must never throw into the caller,
  // or a broken log would break close/interrupt themselves.
  test("an unwritable path is swallowed, never thrown", async () => {
    process.env.LFG_OPS_LOG = "/proc/nonexistent/ops.log"; // unwritable on macOS too
    await expect(logOp({ op: "close", sessionId: "s", ok: true, ms: 1 })).resolves.toBeUndefined();
  });
});

process.on("exit", () => {
  try {
    rmSync(dir, { recursive: true, force: true });
  } catch {}
});
