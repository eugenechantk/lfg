import { describe, expect, test } from "bun:test";
import {
  globMatches,
  hidesCwd,
  isHiddenDirPattern,
  normalizeExcludes,
  normalizeHiddenDir,
} from "./hidden-dirs";

// Mirrors ios/LFGCore/Tests/LFGCoreTests/HiddenDirsTests.swift — the client and
// server matchers must agree or exclusion silently diverges between the local
// backstop filter and the server-side page filter.

describe("normalizeHiddenDir", () => {
  test("collapses repeated and trailing slashes", () => {
    expect(normalizeHiddenDir("/a//b/")).toBe("/a/b");
    expect(normalizeHiddenDir("  /a/b  ")).toBe("/a/b");
  });
  test("rejects relative, tilde, root, and all-wildcard entries", () => {
    expect(normalizeHiddenDir("a/b")).toBeNull();
    expect(normalizeHiddenDir("~/x")).toBeNull();
    expect(normalizeHiddenDir("/")).toBeNull();
    expect(normalizeHiddenDir("*")).toBeNull();
    expect(normalizeHiddenDir("*/?")).toBeNull();
    expect(normalizeHiddenDir("")).toBeNull();
  });
  test("accepts patterns without a leading slash", () => {
    expect(normalizeHiddenDir("*/gbrain-claude-cli-cwd-*")).toBe("*/gbrain-claude-cli-cwd-*");
  });
});

describe("globMatches", () => {
  test("* spans slashes, ? is exactly one char", () => {
    expect(globMatches("*/gbrain-claude-cli-cwd-*", "/var/t/gbrain-claude-cli-cwd-123")).toBe(true);
    expect(globMatches("/a/?", "/a/b")).toBe(true);
    expect(globMatches("/a/?", "/a/bc")).toBe(false);
    expect(globMatches("/a/*", "/a/b/c/d")).toBe(true);
  });
  test("backtracks through multiple stars", () => {
    expect(globMatches("*a*b*", "xaYYbZ")).toBe(true);
    expect(globMatches("*a*b*", "ba")).toBe(false);
  });
});

describe("hidesCwd", () => {
  const gbrain = ["*/gbrain-claude-cli-cwd-*"];

  test("no cwd is never hidden", () => {
    expect(hidesCwd(null, gbrain)).toBe(false);
    expect(hidesCwd(undefined, gbrain)).toBe(false);
    expect(hidesCwd("", gbrain)).toBe(false);
  });

  test("literal entries match on segment boundaries only", () => {
    expect(hidesCwd("/Users/e/.gbrain", ["/Users/e/.gbrain"])).toBe(true);
    expect(hidesCwd("/Users/e/.gbrain/sub", ["/Users/e/.gbrain"])).toBe(true);
    expect(hidesCwd("/Users/e/.gbrainstorm", ["/Users/e/.gbrain"])).toBe(false);
  });

  test("literal matching is case-insensitive", () => {
    expect(hidesCwd("/Users/E/.GBrain", ["/users/e/.gbrain"])).toBe(true);
  });

  test("pattern hides the matched dir and its children", () => {
    const cwd = "/private/var/folders/cd/T/gbrain-claude-cli-cwd-1799";
    expect(hidesCwd(cwd, gbrain)).toBe(true);
    expect(hidesCwd(cwd + "/nested/deep", gbrain)).toBe(true);
    expect(hidesCwd("/Users/e/dev/personal/lfg", gbrain)).toBe(false);
  });

  test("real-world autopilot temp cwd", () => {
    expect(
      hidesCwd("/private/var/folders/fv/T/lfg-autopilot-claude-cwd-1103", [
        "*/lfg-autopilot-claude-cwd-*",
      ]),
    ).toBe(true);
  });

  test("unusable patterns in the list are ignored, not fatal", () => {
    expect(hidesCwd("/Users/e/dev/lfg", ["~", "*", "", "/users/e/dev/lfg"])).toBe(true);
  });
});

describe("normalizeExcludes", () => {
  test("drops unusable entries and keeps order", () => {
    expect(normalizeExcludes(["*/a-*", "~", "/x//y/", "*"])).toEqual(["*/a-*", "/x/y"]);
    expect(normalizeExcludes(undefined)).toEqual([]);
  });
});
