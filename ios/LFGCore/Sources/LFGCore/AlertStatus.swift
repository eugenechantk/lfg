import Foundation

/// One emoji per alert status, at the start of every alert title, so a glance at
/// the lock screen says what happened before the words do. Used by the Mac
/// app's local alerts and the Start Session confirmation; phone pushes get the
/// same titles from the server's `src/alert-title.ts` — keep the two identical.
///
/// Foundation-only: `desktop/build.sh` compiles this file in directly.
public enum AlertStatus: String, CaseIterable, Sendable {
    case completed
    case needsInput = "needs-input"
    case blocked
    case working
    case reminder
    case job
    case started

    public var emoji: String {
        switch self {
        case .completed: return "✅"
        case .needsInput: return "🙋"
        case .blocked: return "⚠️"
        case .working: return "⏳"
        case .reminder: return "🔔"
        case .job: return "📅"
        case .started: return "🚀"
        }
    }

    /// `title` with exactly one status emoji in front: this one. A leading run of
    /// status emoji (with or without U+FE0F) is dropped first, so an agent that
    /// writes "✅ Done" for a reminder gets "🔔 Done", not "🔔 ✅ Done".
    public func title(_ title: String) -> String {
        let scalars = title.unicodeScalars
        let rest = scalars.drop {
            Self.statusScalars.contains($0.value) || $0.value == 0xFE0F
                || CharacterSet.whitespacesAndNewlines.contains($0)
        }
        return rest.isEmpty ? emoji : "\(emoji) \(String(String.UnicodeScalarView(rest)))"
    }

    private static let statusScalars = Set(allCases.compactMap { $0.emoji.unicodeScalars.first?.value })
}

