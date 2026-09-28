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

  test("the system toolbar owns the visible More button and its material", async () => {
    const source = await Bun.file(
      import.meta.dir + "/../ios/LFG/SessionDetailView.swift",
    ).text();
    const start = source.indexOf("private struct NativeSessionOptionsButton");
    const end = source.indexOf("/// The 180° flip", start);
    expect(start).toBeGreaterThanOrEqual(0);
    expect(end).toBeGreaterThan(start);

    const nativeButton = source.slice(start, end);
    expect(nativeButton).toContain("UIButton(type: .system)");
    expect(nativeButton).toContain('button.accessibilityIdentifier = "sessionOptionsMenu"');
    expect(nativeButton).toContain("button.isAccessibilityElement = true");
    expect(nativeButton).toContain("button.showsMenuAsPrimaryAction = true");
    expect(source).toContain(".toolbar { toolbarMenu }");
    expect(source).not.toContain("SessionOptionsNavigationBarProxy");
    expect(source).not.toContain("sessionOptionsMenuDidDismiss");
    expect(source).not.toContain("StableSessionOptionsButton");
    expect(source).not.toContain("UIGlassEffect(style: .regular)");
    expect(source).not.toContain("toolbarBackground(.hidden, for: .navigationBar)");
    expect(source).not.toContain(".sharedBackgroundVisibility(.hidden)");
  });
});
