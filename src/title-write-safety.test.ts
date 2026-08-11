// Guards the one failure this file must never have: losing title overrides the
// human set. `session-titles.json` is written by BOTH `lfg serve` and the
// `lfg autopilot` CLI, so its writer cannot assume it is the only one.

import { afterAll, afterEach, describe, expect, test } from "bun:test";
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// LFG_DATA must be set before `config.ts` is first imported, and static imports
// are evaluated before any of this module's body — hence the dynamic imports
// below. Without this the suite would operate on the real ~/.lfg.
const data = join(tmpdir(), `lfg-titles-${Date.now()}-${Math.random().toString(16).slice(2)}`);
process.env.LFG_DATA = data;
mkdirSync(data, { recursive: true });

const { readTitleRecords, setSessionTitle, updateTitleRecord } = await import("./sessions.ts");
// Read the live value rather than recomputing from `data`: under the full suite
// another test file's LFG_DATA may already have won the first config.ts import.
const { PATHS } = await import("./config.ts");
const path = PATHS.sessionTitles;

afterEach(() => rmSync(path, { force: true }));
afterAll(() => rmSync(data, { recursive: true, force: true }));

const seed = (v: unknown) => writeFileSync(path, JSON.stringify(v, null, 2));

describe("title override writes", () => {
  test("a new title merges instead of replacing the file", async () => {
    seed({ human: "Hand typed", other: { title: "Auto one", source: "auto", setAt: 1 } });
    await setSessionTitle("fresh", "Newly named", { source: "auto" });
    const all = await readTitleRecords();
    expect(Object.keys(all).sort()).toEqual(["fresh", "human", "other"]);
    expect(all.human).toEqual({ title: "Hand typed", source: "user", setAt: 0 });
  });

  test("REFUSES to write when the existing file is unreadable", async () => {
    // The destructive sequence this closes: a reader that degrades a corrupt or
    // half-written file to `{}` would let the next write persist only its own
    // row, wiping every other override. Failing loudly is recoverable.
    writeFileSync(path, '{"human": "Hand typed"'); // truncated mid-write
    await expect(setSessionTitle("fresh", "Newly named", { source: "auto" })).rejects.toThrow(
      /unreadable/,
    );
    // The bytes are still there — untouched, so they can be recovered.
    expect(readFileSync(path, "utf8")).toBe('{"human": "Hand typed"');
  });

  test("an ABSENT file is not treated as corrupt", async () => {
    rmSync(path, { force: true });
    await setSessionTitle("fresh", "Newly named", { source: "auto" });
    expect(Object.keys(await readTitleRecords())).toEqual(["fresh"]);
  });

  test("a batch of concurrent writes keeps every row", async () => {
    seed({ human: "Hand typed" });
    await Promise.all(
      Array.from({ length: 8 }, (_, i) =>
        setSessionTitle(`s${i}`, `Title ${i}`, { source: "auto" }),
      ),
    );
    const all = await readTitleRecords();
    expect(Object.keys(all)).toHaveLength(9);
    expect(all.human.source).toBe("user");
  });

  test("clearing a title drops only that row", async () => {
    seed({ human: "Hand typed", doomed: { title: "Bye", source: "auto", setAt: 1 } });
    await setSessionTitle("doomed", "");
    expect(Object.keys(await readTitleRecords())).toEqual(["human"]);
  });

  test("the write is atomic — no temp file is left behind", async () => {
    seed({ human: "Hand typed" });
    await setSessionTitle("fresh", "Newly named", { source: "auto" });
    expect(readdirSync(PATHS.data).filter((f) => f.includes("session-titles.json.tmp"))).toEqual([]);
    expect(existsSync(path)).toBe(true);
  });

  test("a mutate that throws leaves the file intact", async () => {
    seed({ human: "Hand typed" });
    await expect(
      updateTitleRecord("x", () => {
        throw new Error("boom");
      }),
    ).rejects.toThrow("boom");
    expect(Object.keys(await readTitleRecords())).toEqual(["human"]);
  });
});
