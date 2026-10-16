import { describe, expect, test } from "bun:test";

// The session view's toolbar button. Until S2 it was a native UIMenu
// (`NativeSessionOptionsButton` / `SessionOptionsMenu`); since S2 Phase 3 it is
// a plain UIButton that opens the session sheet (`SessionOptionsButton`). The
// invariants these tests guard carried over: UIKit callbacks hop to the main
// actor instead of asserting their queue, and the system toolbar owns the
// button and its material.
describe("iOS session options button safety", () => {
  async function optionsButtonSource() {
    const source = await Bun.file(
      import.meta.dir + "/../ios/LFG/SessionDetailView.swift",
    ).text();
    const start = source.indexOf("private struct SessionOptionsButton");
    const end = source.indexOf("/// The 180° flip", start);
    expect(start).toBeGreaterThanOrEqual(0);
    expect(end).toBeGreaterThan(start);
    return { source, button: source.slice(start, end) };
  }

  test("UIKit callbacks hop to the main actor instead of asserting their queue", async () => {
    const { button } = await optionsButtonSource();
    expect(button).not.toMatch(/MainActor\.assumeIsolated\s*\{/);
    expect(button.match(/Task \{ @MainActor in/g)?.length).toBeGreaterThanOrEqual(1);
  });

  test("the system toolbar owns the visible options button and its material", async () => {
    const { source, button } = await optionsButtonSource();
    expect(button).toContain("UIButton(type: .system)");
    expect(button).toContain('button.accessibilityIdentifier = "sessionOptionsMenu"');
    expect(button).toContain("button.isAccessibilityElement = true");
    // It opens the session sheet; the old pull-down menu is gone.
    expect(button).not.toContain("showsMenuAsPrimaryAction");
    expect(source).not.toContain("private struct NativeSessionOptionsButton");
    expect(source).toContain(".toolbar { toolbarMenu }");
    expect(source).not.toContain("SessionOptionsNavigationBarProxy");
    expect(source).not.toContain("sessionOptionsMenuDidDismiss");
    expect(source).not.toContain("StableSessionOptionsButton");
    expect(source).not.toContain("UIGlassEffect(style: .regular)");
    expect(source).not.toContain("toolbarBackground(.hidden, for: .navigationBar)");
    expect(source).not.toContain(".sharedBackgroundVisibility(.hidden)");
  });
});
