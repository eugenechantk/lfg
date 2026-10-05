// Regression cover for codex creates into a new folder 504ing "Codex started
// but did not produce a session ID": an untrusted cwd parks codex on its
// "Folder access — Trust this folder?" screen, so no rollout is ever written.
// The block asserted here is byte-for-byte what codex 0.159.2 appended to
// ~/.codex/config.toml when "Trust and continue" was pressed (2026-10-04).
import { test, expect, describe } from "bun:test";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { ensureCodexFolderTrusted } from "./tmux";

function tempConfig(initial?: string): string {
  const p = join(mkdtempSync(join(tmpdir(), "codex-trust-")), "config.toml");
  if (initial !== undefined) writeFileSync(p, initial);
  return p;
}

describe("ensureCodexFolderTrusted", () => {
  test("appends the block codex writes itself", () => {
    const p = tempConfig('model = "gpt-6-astra"\n\n[projects."/a"]\ntrust_level = "trusted"\n');
    ensureCodexFolderTrusted("/Users/x/inbox/new-task", p);
    expect(readFileSync(p, "utf8")).toBe(
      'model = "gpt-6-astra"\n\n[projects."/a"]\ntrust_level = "trusted"\n\n' +
        '[projects."/Users/x/inbox/new-task"]\ntrust_level = "trusted"\n',
    );
  });

  test("is a no-op for a folder that already has an entry", () => {
    const initial = '[projects."/Users/x/inbox"]\ntrust_level = "untrusted"\n';
    const p = tempConfig(initial);
    ensureCodexFolderTrusted("/Users/x/inbox", p);
    expect(readFileSync(p, "utf8")).toBe(initial);
  });

  test("does not mistake a child folder's entry for the parent's", () => {
    const p = tempConfig('[projects."/Users/x/inbox/child"]\ntrust_level = "trusted"\n');
    ensureCodexFolderTrusted("/Users/x/inbox", p);
    expect(readFileSync(p, "utf8")).toContain('[projects."/Users/x/inbox"]\ntrust_level = "trusted"\n');
  });

  test("creates the config when codex has none yet", () => {
    const p = tempConfig();
    ensureCodexFolderTrusted("/tmp/t", p);
    expect(readFileSync(p, "utf8")).toBe('[projects."/tmp/t"]\ntrust_level = "trusted"\n');
  });

  test("handles a config with no trailing newline", () => {
    const p = tempConfig('model = "m"');
    ensureCodexFolderTrusted("/tmp/t", p);
    expect(readFileSync(p, "utf8")).toBe('model = "m"\n\n[projects."/tmp/t"]\ntrust_level = "trusted"\n');
  });
});
