import { describe, expect, test } from "bun:test";
import { parseOpenCodexRollouts } from "./procinfo.ts";

describe("parseOpenCodexRollouts", () => {
  test("maps rollout paths to their owning process", () => {
    const got = parseOpenCodexRollouts(`
p101
fcwd
n/Users/eugenechan/dev/a
f51
au
n/Users/eugenechan/.codex/sessions/2026/08/21/rollout-a.jsonl
p202
f22
aw
n/Users/eugenechan/.codex/sessions/2026/08/22/rollout-b.jsonl
f23
au
n/Users/eugenechan/not-a-rollout.jsonl
`);

    expect(got.get(101)).toEqual([
      "/Users/eugenechan/.codex/sessions/2026/08/21/rollout-a.jsonl",
    ]);
    expect(got.get(202)).toEqual([
      "/Users/eugenechan/.codex/sessions/2026/08/22/rollout-b.jsonl",
    ]);
  });

  test("a read-only rollout descriptor is not ownership (bug 010)", () => {
    // Codex reads OTHER sessions' rollouts at startup (history/picker). A
    // spawn-time lsof snapshot that caught one bound the new session to a
    // days-old rollout and patchManaged made it permanent.
    const got = parseOpenCodexRollouts(`
p55877
f60
ar
n/Users/eugenechan/.codex/sessions/2026/08/20/rollout-stale.jsonl
f66
au
n/Users/eugenechan/.codex/sessions/2026/08/22/rollout-own.jsonl
`);

    expect(got.get(55877)).toEqual([
      "/Users/eugenechan/.codex/sessions/2026/08/22/rollout-own.jsonl",
    ]);
  });

  test("a descriptor with no access mode stays owned (Linux /proc has no mode)", () => {
    const path = "/tmp/.codex/sessions/2026/08/22/rollout-modeless.jsonl";
    const got = parseOpenCodexRollouts(`p7\nf4\nn${path}\n`);

    expect(got.get(7)).toEqual([path]);
  });

  test("deduplicates repeated descriptors and ignores malformed process blocks", () => {
    const path = "/tmp/.codex/sessions/2026/08/22/rollout-current.jsonl";
    const got = parseOpenCodexRollouts(`p7\nf4\nn${path}\nf5\nn${path}\npnope\nn${path}\n`);

    expect(got.get(7)).toEqual([path]);
    expect(got.size).toBe(1);
  });
});
