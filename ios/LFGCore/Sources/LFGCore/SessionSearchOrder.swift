import Foundation

/// Shared by mobile and desktop. Keep the host's `rankSessions` priorities in sync.
public enum SessionSearchOrder {
    public static func priority(terms: [String], cwd: String?, project: String?, title: String?) -> Int {
        guard !terms.isEmpty else { return 0 }
        let directory = [cwd, project].compactMap { $0 }.joined(separator: "\n").lowercased()
        if terms.allSatisfy({ directory.contains($0) }) { return 3 }
        let title = (title ?? "").lowercased()
        return terms.allSatisfy { title.contains($0) } ? 2 : 1
    }

    public static func precedes(priority: Int, activity: Double?, id: String,
                                otherPriority: Int, otherActivity: Double?, otherID: String) -> Bool {
        if priority != otherPriority { return priority > otherPriority }
        let activity = activity ?? 0
        let otherActivity = otherActivity ?? 0
        return activity == otherActivity ? id < otherID : activity > otherActivity
    }
}
