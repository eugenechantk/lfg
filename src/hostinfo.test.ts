import { describe, expect, it } from "bun:test";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { readOrCreateHostId } from "./hostinfo.ts";

function tmp(): string {
  return mkdtempSync(join(tmpdir(), "lfg-hostid-"));
}

describe("readOrCreateHostId", () => {
  it("mints a uuid on first call and persists it to data/host-id", () => {
    const dir = tmp();
    try {
      const id = readOrCreateHostId(dir);
      expect(id).toMatch(
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
      );
      expect(readFileSync(join(dir, "host-id"), "utf8").trim()).toBe(id);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("returns the SAME id on subsequent calls (stable across restarts)", () => {
    const dir = tmp();
    try {
      const first = readOrCreateHostId(dir);
      const second = readOrCreateHostId(dir);
      expect(second).toBe(first);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("honors a pre-seeded host-id file (trims whitespace)", () => {
    const dir = tmp();
    try {
      writeFileSync(join(dir, "host-id"), "  seeded-host-42\n");
      expect(readOrCreateHostId(dir)).toBe("seeded-host-42");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
