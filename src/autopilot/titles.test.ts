import { describe, expect, test } from "bun:test";
import {
  autopilotMayRename,
  flattenTitles,
  parseTitleFile,
  parseTitleRecord,
  type TitleRecord,
} from "./titles.ts";

describe("parseTitleRecord", () => {
  test("a legacy string is a user-set title", () => {
    expect(parseTitleRecord("Flakey connection")).toEqual({
      title: "Flakey connection",
      source: "user",
      setAt: 0,
    });
  });

  test("an empty or whitespace-only legacy string is dropped", () => {
    expect(parseTitleRecord("")).toBeNull();
    expect(parseTitleRecord("   ")).toBeNull();
  });

  test("a full record round-trips", () => {
    const rec: TitleRecord = {
      title: "Autopilot retitle task",
      source: "auto",
      setAt: 1_700_000_000_000,
      basis: 'drifted from "Fix the preamble"',
    };
    expect(parseTitleRecord(rec)).toEqual(rec);
  });

  test("an unknown source falls back to user, not auto", () => {
    // The failure mode that matters is autopilot overwriting a human title, so
    // anything unreadable must land on the side autopilot refuses to touch.
    const rec = parseTitleRecord({ title: "x", source: "robot" });
    expect(rec?.source).toBe("user");
  });

  test("a record with no title is dropped", () => {
    expect(parseTitleRecord({ source: "auto", setAt: 1 })).toBeNull();
    expect(parseTitleRecord({ title: "  ", source: "auto" })).toBeNull();
  });

  test("non-objects are dropped", () => {
    for (const v of [null, undefined, 42, true, []]) {
      expect(parseTitleRecord(v)).toBeNull();
    }
  });

  test("titles are truncated, not rejected", () => {
    const rec = parseTitleRecord({ title: "a".repeat(500), source: "auto" });
    expect(rec?.title.length).toBe(200);
  });

  test("a non-finite setAt falls back to 0 rather than poisoning the record", () => {
    expect(parseTitleRecord({ title: "x", source: "auto", setAt: NaN })?.setAt).toBe(0);
    expect(parseTitleRecord({ title: "x", source: "auto", setAt: Infinity })?.setAt).toBe(0);
  });
});

describe("parseTitleFile", () => {
  test("reads the real legacy file shape", () => {
    const legacy = {
      "49e14373-77fc-4f8e-ab4f-68d844e0ae58": "AutoClipping restyle UI",
      "f688108c-824c-44cc-a3aa-d267c3d6fc6f": "Flakey connection",
    };
    const file = parseTitleFile(legacy);
    expect(Object.keys(file)).toHaveLength(2);
    expect(file["f688108c-824c-44cc-a3aa-d267c3d6fc6f"]).toEqual({
      title: "Flakey connection",
      source: "user",
      setAt: 0,
    });
  });

  test("mixes legacy strings and records in one file", () => {
    const file = parseTitleFile({
      a: "hand typed",
      b: { title: "machine chosen", source: "auto", setAt: 5 },
    });
    expect(file.a.source).toBe("user");
    expect(file.b.source).toBe("auto");
  });

  test("a malformed row costs that row, not the file", () => {
    const file = parseTitleFile({ a: "kept", b: null, c: 7, d: { nope: 1 } });
    expect(Object.keys(file)).toEqual(["a"]);
  });

  test("a non-object file yields an empty map", () => {
    for (const v of [null, undefined, "nope", 3, []]) {
      expect(parseTitleFile(v)).toEqual({});
    }
  });
});

describe("flattenTitles", () => {
  test("produces the flat map existing consumers expect", () => {
    const file = parseTitleFile({
      a: "one",
      b: { title: "two", source: "auto", setAt: 1 },
    });
    expect(flattenTitles(file)).toEqual({ a: "one", b: "two" });
  });

  test("an empty file flattens to an empty map", () => {
    expect(flattenTitles({})).toEqual({});
  });
});

describe("autopilotMayRename", () => {
  test("yes when there is no override at all", () => {
    expect(autopilotMayRename(undefined)).toBe(true);
  });

  test("yes for a title autopilot set itself", () => {
    expect(autopilotMayRename({ title: "x", source: "auto", setAt: 1 })).toBe(true);
  });

  test("never for a human-set title", () => {
    expect(autopilotMayRename({ title: "x", source: "user", setAt: 1 })).toBe(false);
  });

  test("never for a legacy string title", () => {
    const rec = parseTitleRecord("legacy") ?? undefined;
    expect(autopilotMayRename(rec)).toBe(false);
  });
});
