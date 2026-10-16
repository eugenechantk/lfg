import Foundation
import Testing
@testable import LFGCore

@Suite("S2 Files & links sheet")
struct FilesSheetModelTests {
    private let now = 1_800_000_000_000.0
    private let cwd = "/Users/eugene/dev/personal/lfg"

    private func file(_ path: String, _ kind: MediaKind, minutesAgo: Double) -> TranscriptAttachment {
        TranscriptAttachment(ref: MediaRef(raw: path, kind: kind), ts: now - minutesAgo * 60_000)
    }

    @Test("the board's files: Images, Videos, Documents, each row 'folder · age'")
    func boardSections() {
        let resources = TranscriptResources(files: [
            file("\(cwd)/.claude/evidence/fork-before.png", .image, minutesAgo: 6),
            file("\(cwd)/.claude/evidence/fork-after.png", .image, minutesAgo: 4),
            file("\(cwd)/.claude/evidence/fork-opens-right-away.mp4", .video, minutesAgo: 3),
            file("\(cwd)/.claude/evidence/fork-latency.md", .markdown, minutesAgo: 4),
            file("\(cwd)/.claude/release-notes.md", .markdown, minutesAgo: 60),
        ])
        let m = FilesSheetModel(resources, cwd: cwd, nowMs: now)
        #expect(m.sections.map(\.section) == [.images, .videos, .documents])
        #expect(m.sections.map { $0.rows.count } == [2, 1, 2])
        #expect(m.fileCount == 5)
        #expect(m.sections[0].rows[0].title == "fork-before.png")
        #expect(m.sections[0].rows[0].meta == ".claude/evidence · 6m ago")
        #expect(m.sections[2].rows[1].meta == ".claude · 1h ago")
    }

    @Test("PDFs and other files are documents; empty sections are left out")
    func documents() {
        let resources = TranscriptResources(files: [file("/tmp/report.pdf", .pdf, minutesAgo: 2)])
        let m = FilesSheetModel(resources, cwd: cwd, nowMs: now)
        #expect(m.sections.map(\.section) == [.documents])
        #expect(m.sections[0].rows[0].meta == "/tmp · 2m ago")
    }

    @Test("folders: inside the session read relative, outside from home, the session's own folder says nothing")
    func folders() {
        #expect(FilesSheetModel.folder("\(cwd)/out/a.png", cwd: cwd) == "out")
        #expect(FilesSheetModel.folder("\(cwd)/a.png", cwd: cwd) == nil)
        #expect(FilesSheetModel.folder("/Users/eugene/Downloads/a.png", cwd: cwd) == "~/Downloads")
        #expect(FilesSheetModel.folder("https://cdn.example.com/a.png", cwd: cwd) == "cdn.example.com")
        #expect(FilesSheetModel.folder("a.png", cwd: cwd) == nil)
    }

    @Test("links show their title, the domain alone, and the domain's initial (board Links tab)")
    func links() {
        let resources = TranscriptResources(links: [
            TranscriptLink(link: WebLink(url: "https://developer.apple.com/documentation/swiftui", label: "SwiftUI docs"),
                           ts: now - 120_000),
        ])
        let m = FilesSheetModel(resources, cwd: cwd, nowMs: now)
        #expect(m.links.count == 1)
        #expect(m.links[0].title == "SwiftUI docs")
        #expect(m.links[0].meta == "developer.apple.com")
        #expect(m.links[0].initial == "D")
        let www = FilesSheetModel(TranscriptResources(links: [TranscriptLink(link: WebLink(url: "https://www.github.com/x"), ts: nil)]),
                                  cwd: cwd, nowMs: now)
        #expect(www.links[0].initial == "G")
    }
}
