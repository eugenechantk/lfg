import { describe, expect, test } from "bun:test";
import { parseThreadForkResponse } from "./codex-app-server.ts";

const source = "00000000-0000-4000-8000-000000000001";
const fork = "00000000-0000-4000-8000-000000000002";

describe("Codex app-server thread fork", () => {
  test("accepts a distinct lineage-preserving fork id", () => {
    expect(parseThreadForkResponse({
      id: 2,
      result: { thread: { id: fork, forkedFromId: source } },
    }, source)).toBe(fork);
  });

  test("rejects errors, reused ids, and wrong lineage", () => {
    expect(() => parseThreadForkResponse({ id: 2, error: { message: "locked" } }, source))
      .toThrow("locked");
    expect(() => parseThreadForkResponse({
      id: 2,
      result: { thread: { id: source, forkedFromId: source } },
    }, source)).toThrow("distinct thread ID");
    expect(() => parseThreadForkResponse({
      id: 2,
      result: { thread: { id: fork, forkedFromId: "00000000-0000-4000-8000-000000000003" } },
    }, source)).toThrow("unexpected source");
  });
});
