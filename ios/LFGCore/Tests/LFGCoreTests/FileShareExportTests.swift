import Foundation
import Testing
@testable import LFGCore

@Suite("File share export")
struct FileShareExportTests {
    @Test("copies the downloaded bytes under the intended filename")
    func copiesDownloadedFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("download.tmp")
        let expected = Data("original image bytes".utf8)
        try expected.write(to: source)

        let export = try FileShareExport.prepare(
            downloadedFile: source,
            filename: "Trip Photo.JPG",
            temporaryDirectory: root
        )

        #expect(export.fileURL.lastPathComponent == "Trip Photo.JPG")
        #expect(try Data(contentsOf: export.fileURL) == expected)
        #expect(export.directoryURL.deletingLastPathComponent() == root)
    }

    @Test("repeated exports are isolated even when the filename is identical")
    func isolatesRepeatedExports() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("download.tmp")
        try Data([1, 2, 3]).write(to: source)

        let first = try FileShareExport.prepare(
            downloadedFile: source,
            filename: "report.pdf",
            temporaryDirectory: root
        )
        let second = try FileShareExport.prepare(
            downloadedFile: source,
            filename: "report.pdf",
            temporaryDirectory: root
        )

        #expect(first.fileURL != second.fileURL)
        #expect(first.fileURL.lastPathComponent == second.fileURL.lastPathComponent)
    }

    @Test("path-like and empty names cannot escape the export directory")
    func sanitizesFilename() {
        #expect(FileShareExport.safeFilename("../../secret.pdf") == "secret.pdf")
        #expect(FileShareExport.safeFilename(#"C:\Users\e\clip.mov"#) == "clip.mov")
        #expect(FileShareExport.safeFilename("") == "file")
        #expect(FileShareExport.safeFilename("..") == "file")
    }

    @Test("cleanup removes the whole isolated export")
    func cleansUpExport() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("download.tmp")
        try Data([4, 5, 6]).write(to: source)
        let export = try FileShareExport.prepare(
            downloadedFile: source,
            filename: "clip.mp4",
            temporaryDirectory: root
        )

        FileShareExport.cleanup(export)

        #expect(!FileManager.default.fileExists(atPath: export.directoryURL.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lfg-file-share-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
