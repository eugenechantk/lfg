import Foundation

/// The desktop Tasks page's "By directory" mode and its hidden-directory filter,
/// the same two options the Sessions list's host strip offers.
public enum TaskDirectoryGrouping {
    /// A task's folder name, as the Sessions list labels a session's project.
    public static func directoryName(_ task: ScheduledTaskRecord) -> String {
        let trimmed = task.cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "—" }
        let name = (trimmed as NSString).lastPathComponent
        return name.isEmpty ? trimmed : name
    }

    /// Groups by folder name, A–Z (case-insensitive); items keep the order they
    /// came in, which is the list's own sort.
    public static func sections<Item>(
        _ items: [Item], task: (Item) -> ScheduledTaskRecord
    ) -> [(directory: String, items: [Item])] {
        var buckets: [String: [Item]] = [:]
        for item in items { buckets[directoryName(task(item)), default: []].append(item) }
        return buckets.keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { (directory: $0, items: buckets[$0]!) }
    }

    /// Drops tasks whose folder is hidden, by the Sessions list's rule.
    public static func visible<Item>(
        _ items: [Item], hidden: HiddenDirs, task: (Item) -> ScheduledTaskRecord
    ) -> [Item] {
        guard !hidden.isEmpty else { return items }
        return items.filter { !hidden.hides(cwd: task($0).cwd) }
    }
}
