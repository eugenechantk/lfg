import { describe, expect, test } from "bun:test";
import { ALERT_EMOJI, alertTitle } from "./alert-title";

describe("alertTitle", () => {
  test("every status gets its own emoji in front", () => {
    expect(alertTitle("completed", "Fix alerts")).toBe("✅ Fix alerts");
    expect(alertTitle("needs-input", "Fix alerts")).toBe("🙋 Fix alerts");
    expect(alertTitle("blocked", "Fix alerts")).toBe("⚠️ Fix alerts");
    expect(alertTitle("working", "Fix alerts")).toBe("⏳ Fix alerts");
    expect(alertTitle("reminder", "Fix alerts")).toBe("🔔 Fix alerts");
    expect(alertTitle("job", "Daily review")).toBe("📅 Daily review");
    expect(alertTitle("started", "lfg")).toBe("🚀 lfg");
    expect(new Set(Object.values(ALERT_EMOJI)).size).toBe(Object.keys(ALERT_EMOJI).length);
  });

  test("a status emoji the title already carries is replaced, never doubled", () => {
    expect(alertTitle("completed", "✅ Done")).toBe("✅ Done");
    expect(alertTitle("reminder", "✅ Done")).toBe("🔔 Done");
    expect(alertTitle("blocked", "⚠ ⚠️  Out of credits")).toBe("⚠️ Out of credits");
    expect(alertTitle("completed", "🎉 Shipped")).toBe("✅ 🎉 Shipped");
    expect(alertTitle("completed", "  ")).toBe("✅");
  });
});

