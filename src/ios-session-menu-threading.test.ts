import { describe, expect, test } from "bun:test";

describe("iOS native session menu safety", () => {
  test("UIKit callbacks hop to the main actor instead of asserting their queue", async () => {
    const source = await Bun.file(
      import.meta.dir + "/../ios/LFG/SessionDetailView.swift",
    ).text();
    const start = source.indexOf("private struct SessionOptionsMenu");
    const end = source.indexOf("/// The 180° flip", start);
    expect(start).toBeGreaterThanOrEqual(0);
    expect(end).toBeGreaterThan(start);

    const nativeMenuBridge = source.slice(start, end);
    expect(nativeMenuBridge).not.toMatch(/MainActor\.assumeIsolated\s*\{/);
    expect(nativeMenuBridge.match(/Task \{ @MainActor in/g)?.length).toBeGreaterThanOrEqual(2);
  });

  test("the navigation proxy walks UIKit view hierarchies iteratively", async () => {
    const source = await Bun.file(
      import.meta.dir + "/../ios/LFG/SessionDetailView.swift",
    ).text();
    const start = source.indexOf("private static func navigationBar(in view: UIView)");
    const end = source.indexOf("/// A transparent 44-point", start);
    expect(start).toBeGreaterThanOrEqual(0);
    expect(end).toBeGreaterThan(start);

    const proxySearches = source.slice(start, end);
    expect(proxySearches).not.toContain("compactMap(navigationBar(in:))");
    expect(proxySearches).not.toContain("compactMap(sessionOptionsSource(in:))");
    expect(proxySearches.match(/while let candidate = pending\.popLast\(\)/g)?.length).toBe(2);
  });
});
