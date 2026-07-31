import { describe, expect, test } from "bun:test";
import { pickSingleCodexCreateFallbackCandidate } from "./serve.ts";

const cwd = "/Users/eugenechan/dev/personal/lfg";
const spawnedAt = Date.parse("2026-07-31T12:00:00.000Z");

function candidate(id: string, createdAt = spawnedAt + 1_500) {
  return { id, cwd, createdAt };
}

describe("codex create-session fallback binding", () => {
  test("binds when exactly one unclaimed same-cwd rollout was created after spawn", () => {
    const got = pickSingleCodexCreateFallbackCandidate({
      cwd,
      spawnedAt,
      candidates: [
        candidate("00000000-0000-4000-8000-000000000001"),
        { ...candidate("00000000-0000-4000-8000-000000000002"), cwd: "/other/repo" },
        candidate("00000000-0000-4000-8000-000000000003", spawnedAt - 1),
      ],
    });

    expect(got?.id).toBe("00000000-0000-4000-8000-000000000001");
  });

  test("returns null when two unclaimed same-cwd rollouts are fallback candidates", () => {
    const got = pickSingleCodexCreateFallbackCandidate({
      cwd,
      spawnedAt,
      candidates: [
        candidate("00000000-0000-4000-8000-000000000001"),
        candidate("00000000-0000-4000-8000-000000000002", spawnedAt + 2_000),
      ],
    });

    expect(got).toBeNull();
  });

  test("returns null when the only same-cwd fallback candidate is already claimed", () => {
    const id = "00000000-0000-4000-8000-000000000001";
    const got = pickSingleCodexCreateFallbackCandidate({
      cwd,
      spawnedAt,
      candidates: [candidate(id)],
      claimedIds: new Set([id]),
    });

    expect(got).toBeNull();
  });
});
