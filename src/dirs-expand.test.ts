// `~` is a shell feature. A directory path typed into the iOS client's "Add
// directory by path…" field travels JSON → fetch → statSync, and nothing on
// that route is a shell — so `~/dev/inbox` used to 400 as "directory not found"
// for a directory that plainly exists. These pin the normalization that fixes it.
import { describe, expect, test } from "bun:test";
import { homedir } from "node:os";
import { join } from "node:path";
import { expandUserPath } from "./dirs.ts";

describe("expandUserPath", () => {
  test("expands a leading ~/", () => {
    expect(expandUserPath("~/dev/inbox")).toBe(join(homedir(), "dev/inbox"));
  });

  test("expands a bare ~", () => {
    expect(expandUserPath("~")).toBe(homedir());
  });

  test("trims surrounding whitespace before expanding", () => {
    expect(expandUserPath("  ~/dev/inbox  ")).toBe(join(homedir(), "dev/inbox"));
  });

  test("leaves an absolute path alone", () => {
    expect(expandUserPath("/Users/someone/dev/inbox")).toBe("/Users/someone/dev/inbox");
  });

  test("strips trailing separators so the echoed cwd is canonical", () => {
    expect(expandUserPath("/Users/someone/dev/inbox/")).toBe("/Users/someone/dev/inbox");
    expect(expandUserPath("/Users/someone/dev/inbox///")).toBe("/Users/someone/dev/inbox");
  });

  test("keeps a bare root intact", () => {
    expect(expandUserPath("/")).toBe("/");
  });

  test("does NOT anchor a relative path to the server's cwd", () => {
    // Resolving here would silently accept `dev/inbox` as some directory under
    // wherever `lfg serve` happens to run. It must stay relative so the caller's
    // existence check rejects it.
    expect(expandUserPath("dev/inbox")).toBe("dev/inbox");
  });

  test("only expands ~ at the start", () => {
    expect(expandUserPath("/tmp/~/notahome")).toBe("/tmp/~/notahome");
  });

  test("empty input stays empty so callers can apply their own default", () => {
    expect(expandUserPath("   ")).toBe("");
  });
});
