import Testing
@testable import LFGCore

@Suite struct AlertStatusTests {
    // Must match src/alert-title.ts ALERT_EMOJI — phone pushes and Mac alerts
    // read the same at a glance.
    @Test func everyStatusHasItsOwnEmoji() {
        #expect(AlertStatus.completed.title("Fix alerts") == "✅ Fix alerts")
        #expect(AlertStatus.needsInput.title("Fix alerts") == "🙋 Fix alerts")
        #expect(AlertStatus.blocked.title("Fix alerts") == "⚠️ Fix alerts")
        #expect(AlertStatus.working.title("Fix alerts") == "⏳ Fix alerts")
        #expect(AlertStatus.reminder.title("Fix alerts") == "🔔 Fix alerts")
        #expect(AlertStatus.job.title("Daily review") == "📅 Daily review")
        #expect(AlertStatus.started.title("lfg") == "🚀 lfg")
        #expect(Set(AlertStatus.allCases.map(\.emoji)).count == AlertStatus.allCases.count)
        #expect(AlertStatus(rawValue: "needs-input") == .needsInput)
    }

    @Test func anEmojiTheTitleAlreadyCarriesIsReplacedNotDoubled() {
        #expect(AlertStatus.completed.title("✅ Done") == "✅ Done")
        #expect(AlertStatus.reminder.title("✅ Done") == "🔔 Done")
        #expect(AlertStatus.blocked.title("⚠ ⚠️  Out of credits") == "⚠️ Out of credits")
        #expect(AlertStatus.completed.title("🎉 Shipped") == "✅ 🎉 Shipped")
        #expect(AlertStatus.completed.title("  ") == "✅")
    }

}
