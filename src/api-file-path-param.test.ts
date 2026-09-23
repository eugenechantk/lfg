// `?path=` carries a filesystem path, not form data. The two decodings disagree
// on exactly one character — `+` — and Foundation leaves `+` unescaped because
// it is legal in a query, so every screenshot named `…-t+3.5s.jpg` 404'd.
import { describe, expect, test } from "bun:test";
import { filePathCandidates } from "./commands/serve.ts";

const at = (query: string) => new URL(`http://h/api/file?${query}`);

describe("filePathCandidates", () => {
  test("a literal + is offered before the form reading", () => {
    const c = filePathCandidates(at("path=/e/shot-t+3.5s.jpg&w=1200"));
    expect(c[0]).toBe("/e/shot-t+3.5s.jpg");
    expect(c).toContain("/e/shot-t 3.5s.jpg");
  });

  test("a percent-encoded plus needs no fallback", () => {
    expect(filePathCandidates(at("path=/e/shot-t%2B3.5s.jpg"))).toEqual(["/e/shot-t+3.5s.jpg"]);
  });

  test("a percent-encoded space is a space, with no second reading", () => {
    expect(filePathCandidates(at("path=/e/AI%20girl%20game/a.png"))).toEqual([
      "/e/AI girl game/a.png",
    ]);
  });

  test("an ordinary path yields exactly one candidate", () => {
    expect(filePathCandidates(at("path=/e/out/chart.png&w=2400"))).toEqual(["/e/out/chart.png"]);
  });

  test("the path param is found wherever it sits in the query", () => {
    expect(filePathCandidates(at("w=1200&path=/e/a+b.png"))[0]).toBe("/e/a+b.png");
  });

  test("a missing path yields nothing", () => {
    expect(filePathCandidates(at("w=1200"))).toEqual([]);
  });

  test("a malformed escape falls back to the form reading rather than throwing", () => {
    expect(filePathCandidates(at("path=/e/%zz+x.png"))).toEqual(["/e/%zz x.png"]);
  });
});
