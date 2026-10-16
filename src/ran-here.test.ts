import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createRanHereLedger } from "./ran-here.ts";

const dir = mkdtempSync(join(tmpdir(), "lfg-ran-here-"));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

describe("ran-here ledger", () => {
  test("remembers when a session was last seen running here, across restarts", async () => {
    const path = join(dir, "a.json");
    const ledger = createRanHereLedger(path);
    expect(ledger.at("s1")).toBeNull();
    await ledger.note(["s1", "s2"], 1_000);
    expect(ledger.at("s1")).toBe(1_000);
    // A fresh instance is a server restart: it reads what the last one wrote.
    expect(createRanHereLedger(path).at("s2")).toBe(1_000);
  });

  test("skips rewrites for small advances but keeps new sessions at once", async () => {
    const path = join(dir, "b.json");
    const ledger = createRanHereLedger(path, { minAdvanceMs: 60_000 });
    await ledger.note(["s1"], 1_000);
    await ledger.note(["s1"], 31_000);
    expect(ledger.at("s1")).toBe(1_000);
    await ledger.note(["s1", "s2"], 32_000);
    expect(ledger.at("s1")).toBe(1_000);
    expect(createRanHereLedger(path).at("s2")).toBe(32_000);
    await ledger.note(["s1"], 61_000);
    expect(createRanHereLedger(path).at("s1")).toBe(61_000);
  });

  test("keeps only the newest entries when over the cap", async () => {
    const path = join(dir, "c.json");
    const ledger = createRanHereLedger(path, { maxEntries: 2 });
    await ledger.note(["old"], 1);
    await ledger.note(["mid"], 2);
    await ledger.note(["new"], 3);
    expect(Object.keys(JSON.parse(readFileSync(path, "utf8"))).sort()).toEqual(["mid", "new"]);
    expect(ledger.at("old")).toBeNull();
  });

  test("a corrupt file reads as empty instead of failing", () => {
    const path = join(dir, "d.json");
    writeFileSync(path, "{not json");
    expect(createRanHereLedger(path).at("s1")).toBeNull();
  });
});
