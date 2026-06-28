import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { rmSync, mkdtempSync } from "node:fs";

let dir: string;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "lfg-push-"));
  process.env.LFG_PUSH_STORE = join(dir, "push-devices.json");
});
afterEach(() => {
  delete process.env.LFG_PUSH_STORE;
  rmSync(dir, { recursive: true, force: true });
});

// Import lazily after the env is set so the module reads the temp path.
async function store() {
  return await import("./store.ts");
}

describe("device store (SC4)", () => {
  test("empty store lists nothing", async () => {
    const s = await store();
    expect(await s.listDevices()).toEqual([]);
    expect(await s.deviceCount()).toBe(0);
  });

  test("register persists a device and dedupes by token", async () => {
    const s = await store();
    await s.registerDevice({ token: "tok1", env: "sandbox", owner: "me@x.com" });
    await s.registerDevice({ token: "tok1", env: "production" }); // same token, new env
    const list = await s.listDevices();
    expect(list.length).toBe(1);
    expect(list[0].env).toBe("production");
    expect(list[0].owner).toBe("me@x.com"); // preserved across upsert
  });

  test("registration survives a fresh read (restart)", async () => {
    const s = await store();
    await s.registerDevice({ token: "tok2", env: "sandbox" });
    // Re-read from disk (the module reads the file every call — simulates restart).
    const again = await s.listDevices();
    expect(again.map((d) => d.token)).toContain("tok2");
  });

  test("unregister removes a device", async () => {
    const s = await store();
    await s.registerDevice({ token: "a", env: "sandbox" });
    await s.registerDevice({ token: "b", env: "sandbox" });
    await s.unregisterDevice("a");
    const list = await s.listDevices();
    expect(list.map((d) => d.token)).toEqual(["b"]);
  });
});
