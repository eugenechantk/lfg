import Foundation

/// The composer's model chip (S2, canvas board `s2-view`): "Opus 5.5 · High".
/// Hosts send raw ids ("claude-opus-5-5"), so this turns them into the names
/// the CLIs' own pickers use. An id it does not recognise passes through.
public enum ModelChipLabel {
    public static func text(model: String?, effort: String?) -> String {
        let name = model.map(Self.model) ?? "Model"
        guard let effort, !effort.isEmpty else { return name }
        return "\(name) · \(SessionEffort.displayName(effort))"
    }

    public static func model(_ id: String) -> String {
        let lower = id.lowercased()
        if lower.hasPrefix("gpt-") {
            let rest = id.dropFirst(4).split(separator: "-")
            guard let version = rest.first else { return id }
            let words = rest.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }
            return (["GPT-\(version)"] + words).joined(separator: " ")
        }
        var parts = lower.split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        guard let family = parts.first, SessionEffort.claudeFamily(of: family) == family else { return id }
        // Version digits follow the family; a trailing date stamp is dropped.
        let version = parts.dropFirst().prefix { $0.count <= 2 && $0.allSatisfy(\.isNumber) }
        let name = family.prefix(1).uppercased() + family.dropFirst()
        return version.isEmpty ? name : "\(name) \(version.joined(separator: "."))"
    }
}
