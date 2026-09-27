import Foundation

/// A local file kept alive while iOS presents its activity sheet.
///
/// URLSession owns and may reclaim its download URL after the request finishes,
/// so sharing that URL directly is racy. Each export gets a private directory;
/// the caller removes it after the sheet is dismissed.
public struct PreparedFileShareExport: Equatable, Identifiable, Sendable {
    public let fileURL: URL
    public let directoryURL: URL
    public var id: URL { fileURL }

    public init(fileURL: URL, directoryURL: URL) {
        self.fileURL = fileURL
        self.directoryURL = directoryURL
    }
}

public enum FileShareExport {
    /// Copy a completed download to a stable, named local URL for the activity sheet.
    public static func prepare(
        downloadedFile: URL,
        filename: String,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) throws -> PreparedFileShareExport {
        let directory = temporaryDirectory
            .appendingPathComponent("lfg-share-\(UUID().uuidString)", isDirectory: true)
        let destination = directory.appendingPathComponent(safeFilename(filename), isDirectory: false)

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: downloadedFile, to: destination)
            return PreparedFileShareExport(fileURL: destination, directoryURL: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    public static func cleanup(_ export: PreparedFileShareExport) {
        try? FileManager.default.removeItem(at: export.directoryURL)
    }

    /// Keep only a usable final path component while preserving the human name,
    /// spaces, Unicode, case, and extension that inform the system share actions.
    public static func safeFilename(_ filename: String) -> String {
        let normalized = filename.replacingOccurrences(of: "\\", with: "/")
        let finalComponent = normalized
            .split(separator: "/", omittingEmptySubsequences: true)
            .last
            .map(String.init) ?? ""
        let withoutControls = finalComponent.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) ? "_" : String(scalar)
        }.joined()
        let trimmed = withoutControls.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "." || trimmed == ".." ? "file" : trimmed
    }
}
