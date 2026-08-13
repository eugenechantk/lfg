// The attachments sheet is only as good as what this finds, and the parsing has
// a lot of edges: a path is a path whether it arrived as markdown, an image, or
// bare prose; a URL ending in .png is a file, not a link; a tool call mentioning
// forty paths is noise, not attachments.
import Testing
import Foundation
@testable import LFGCore

private func msg(_ text: String, kind: String = "text", role: String = "assistant", ts: Double? = nil) -> SessionMessage {
    SessionMessage(id: UUID().uuidString, role: role, kind: kind, text: text, ts: ts)
}

@Suite("Transcript resource index")
struct TranscriptResourceIndexTests {
    @Test("collects files from markdown images, links and bare paths")
    func collectsEveryReferenceShape() {
        let r = TranscriptResourceIndex.collect(from: [
            msg("![chart](/Users/e/out/chart.png)"),
            msg("[the report](/Users/e/out/report.pdf)"),
            msg("Rendered to /Users/e/out/clip.mp4 just now."),
        ])
        #expect(r.files.map(\.ref.raw) == [
            "/Users/e/out/clip.mp4",         // newest first
            "/Users/e/out/report.pdf",
            "/Users/e/out/chart.png",
        ])
        #expect(r.files.map(\.ref.kind) == [.video, .pdf, .image])
    }

    @Test("newest first, and a repeat keeps its first label")
    func dedupesKeepingNewest() {
        let r = TranscriptResourceIndex.collect(from: [
            msg("[original name](/out/a.png)", ts: 100),
            msg("later mention of /out/a.png", ts: 200),
            msg("[b](/out/b.pdf)", ts: 300),
        ])
        #expect(r.files.count == 2)
        #expect(r.files[0].ref.raw == "/out/b.pdf")
        // Walking newest→oldest, the newest mention is the one kept — the later
        // bare path has no label, which is exactly what that turn showed.
        #expect(r.files[1].ref.raw == "/out/a.png")
        #expect(r.files[1].ts == 200)
    }

    @Test("tool calls and results are ignored")
    func ignoresToolNoise() {
        // A single Bash turn can name dozens of paths. None were handed over.
        let r = TranscriptResourceIndex.collect(from: [
            msg("Read: {\"file_path\": \"/repo/src/index.ts\"}", kind: "tool_use"),
            msg("/repo/a.png\n/repo/b.png\n/repo/c.png", kind: "tool_result", role: "user"),
            msg("thinking about /repo/secret.png", kind: "thinking"),
            msg("Here it is: /repo/real.png"),
        ])
        #expect(r.files.map(\.ref.raw) == ["/repo/real.png"])
    }

    @Test("user uploads are collected too")
    func includesUserTurns() {
        let r = TranscriptResourceIndex.collect(from: [
            msg("[screenshot.png](/uploads/screenshot.png)", role: "user"),
        ])
        #expect(r.files.map(\.ref.raw) == ["/uploads/screenshot.png"])
    }

    @Test("empty transcript yields nothing")
    func emptyIsEmpty() {
        #expect(TranscriptResourceIndex.collect(from: []).isEmpty)
        #expect(TranscriptResourceIndex.collect(from: [msg("no files here at all")]).isEmpty)
    }
}

@Suite("Web links")
struct LinkScannerTests {
    @Test("bare and markdown links are both found, labels preserved")
    func findsBothShapes() {
        let links = LinkScanner.scan("See [the PR](https://github.com/o/r/pull/9) and https://vercel.com/dash")
        #expect(links.map(\.url) == ["https://github.com/o/r/pull/9", "https://vercel.com/dash"])
        #expect(links[0].label == "the PR")
        #expect(links[1].label == nil)
    }

    @Test("a URL that is a file is not also a link")
    func fileURLsAreNotLinks() {
        // Otherwise a remote image appears once as an attachment and once as a
        // link — the same thing, listed twice.
        let text = "![shot](https://cdn.example.com/shot.png) and https://example.com/docs"
        let refs = MediaScanner.scan(text, includeInlineImages: true)
        let links = LinkScanner.scan(text, excluding: Set(refs.map(\.raw)))
        #expect(links.map(\.url) == ["https://example.com/docs"])
    }

    @Test("trailing sentence punctuation is not part of the URL")
    func trimsTrailingPunctuation() {
        #expect(LinkScanner.scan("Go to https://example.com/x.").map(\.url) == ["https://example.com/x"])
        #expect(LinkScanner.scan("(see https://example.com/y)").map(\.url) == ["https://example.com/y"])
    }

    @Test("display name prefers the label, then the distinguishing path segment")
    func displayNamePrefersTheDistinguishingPart() {
        #expect(WebLink(url: "https://claude.ai/design/x", label: "the design").displayName == "the design")
        // Eight links to one host must not render as eight identical rows.
        #expect(WebLink(url: "https://eugenechantk.me/pages/twelve-week-shape-e7f8bdad/").displayName
                == "twelve-week-shape-e7f8bdad")
        #expect(WebLink(url: "https://www.github.com/o/r").displayName == "r")
        // Nothing to distinguish — the host is all there is.
        #expect(WebLink(url: "https://example.com").displayName == "example.com")
        #expect(WebLink(url: "https://www.example.com/").displayName == "example.com")
    }

    @Test("host strips www and is nil for a non-URL")
    func hostNormalizes() {
        #expect(WebLink(url: "https://www.github.com/a/b").host == "github.com")
        #expect(WebLink(url: "https://claude.ai/x").host == "claude.ai")
    }

    @Test("duplicates collapse across the transcript")
    func dedupesLinks() {
        let r = TranscriptResourceIndex.collect(from: [
            msg("https://example.com/a", ts: 1),
            msg("again https://example.com/a", ts: 2),
        ])
        #expect(r.links.count == 1)
    }
}
