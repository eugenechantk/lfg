import Testing
@testable import LFGCore

@Suite("Transcript file cards replace duplicate links")
struct TranscriptFileCardPresentationTests {
    @Test("the reported HTML handoff is one card without prose")
    func htmlHandoff() {
        let path = "/Users/e/report/capture-filing-and-topics.html"
        let row = TranscriptRowText.derive(from: "[capture-filing-and-topics.html](\(path))")
        #expect(row.prose.isEmpty)
        #expect(row.media == [MediaRef(raw: path, kind: .other, label: "capture-filing-and-topics.html")])
    }

    @Test("all card file types replace their markdown links", arguments: ["mp4", "mov", "pdf", "png", "md", "zip"])
    func fileTypes(_ ext: String) {
        let path = "/tmp/export.\(ext)"
        let row = TranscriptRowText.derive(from: "[Open export](\(path))")
        #expect(row.prose.isEmpty)
        #expect(row.media.count == 1)
        #expect(row.media.first?.raw == path)
        #expect(row.media.first?.label == "Open export")
    }

    @Test("duplicate links and bare references retain one ordered card")
    func repeatedReferences() {
        let row = TranscriptRowText.derive(from: "[clip](/tmp/clip.mp4)\n/tmp/clip.mp4\n[clip again](/tmp/clip.mp4)")
        #expect(row.prose.isEmpty)
        #expect(row.media == [MediaRef(raw: "/tmp/clip.mp4", kind: .video, label: "clip")])
    }

    @Test("spaced destinations and link titles leave no link syntax")
    func spacedAndTitled() {
        let row = TranscriptRowText.derive(from: "[Report](</Users/e/My Project/report final.html>)\n[Clip](/tmp/clip.mp4 \"Movie\")")
        #expect(row.prose.isEmpty)
        #expect(row.media.map(\.raw) == ["/Users/e/My Project/report final.html", "/tmp/clip.mp4"])
    }

    @Test("surrounding prose and ordinary website links survive")
    func ordinaryProse() {
        let row = TranscriptRowText.derive(from: "The export is ready.\n\n[Report](/tmp/report.html)\n\nSee [the docs](https://example.com/docs) for details.")
        #expect(row.prose.contains("The export is ready."))
        #expect(row.prose.contains("[the docs](https://example.com/docs)"))
        #expect(!row.prose.contains("[Report]"))
        #expect(row.media.count == 1)
    }

    @Test("paths without cards remain in the transcript")
    func unclaimedPaths() {
        let source = "Source: /tmp/config.json and https://example.com/docs"
        let row = TranscriptRowText.derive(from: source)
        #expect(row.media.isEmpty)
        #expect(row.prose == source)
    }

    @Test("fenced code keeps paths and literal markdown links")
    func fencedCode() {
        let code = "```sh\ncat /tmp/report.pdf\nprintf '[report](/tmp/report.pdf)'\n```"
        let row = TranscriptRowText.derive(from: "[Report](/tmp/report.pdf)\n\n\(code)")
        #expect(row.prose == code)
        #expect(row.media.count == 1)
    }

    @Test("inline commands keep their paths")
    func inlineCode() {
        let row = TranscriptRowText.derive(from: "Run `open /tmp/report.pdf` after downloading.\n[Report](/tmp/report.pdf)")
        #expect(row.prose == "Run `open /tmp/report.pdf` after downloading.")
    }

    @Test("inline commands with inner backticks keep their complete contents")
    func nestedInlineCode() {
        let command = "Run ``echo `/tmp/report.pdf` `` after downloading."
        let row = TranscriptRowText.derive(from: "\(command)\n[Report](/tmp/report.pdf)")
        #expect(row.prose == command)
    }

    @Test("a backticked path handoff becomes only a card")
    func backtickedHandoff() {
        let row = TranscriptRowText.derive(from: "`/tmp/clip.mp4`")
        #expect(row.prose.isEmpty)
        #expect(row.media.count == 1)
    }

    @Test("file-only lists leave no empty bullets or numbers")
    func fileOnlyList() {
        let row = TranscriptRowText.derive(from: "- [Report](/tmp/report.html)\n1. [Clip](/tmp/clip.mp4)")
        #expect(row.prose.isEmpty)
        #expect(row.media.map(\.raw) == ["/tmp/report.html", "/tmp/clip.mp4"])
    }

    @Test("nested list handoffs are prose, rather than indented code")
    func nestedFileList() {
        for source in ["- Exports\n    - [Report](/tmp/report.html)",
                       "1. Exports\n    [Report](/tmp/report.html)"] {
            let row = TranscriptRowText.derive(from: source)
            #expect(!row.prose.contains("[Report]"))
            #expect(!row.prose.contains("/tmp/report.html"))
            #expect(row.media.count == 1)
        }
    }

    @Test("user attachments keep their existing card-only rendering")
    func userAttachment() {
        let row = TranscriptRowText.derive(from: "Look at this [shot](/tmp/shot.png)", extractFollowups: false)
        #expect(row.displayText == "Look at this")
        #expect(row.media.count == 1)
    }

    @Test("a shorter filename does not corrupt another card's link")
    func sharedPrefix() {
        let row = TranscriptRowText.derive(from: "[first](/tmp/a.png)\n[second](/tmp/a.png.extra.png)")
        #expect(row.prose.isEmpty)
        #expect(row.media.map(\.raw) == ["/tmp/a.png", "/tmp/a.png.extra.png"])
    }

    @Test("a card does not remove a prefix from an unrelated path")
    func unrelatedPrefix() {
        let row = TranscriptRowText.derive(from: "[first](/tmp/a.png)\nKeep /tmp/a.png.backup here.")
        #expect(row.prose == "Keep /tmp/a.png.backup here.")
    }

    @Test("autolink file references render only their card")
    func autolink() {
        let row = TranscriptRowText.derive(from: "<https://example.com/movie.mp4>")
        #expect(row.prose.isEmpty)
        #expect(row.media.count == 1)
    }

    @Test("tilde fences and indented code preserve literal references")
    func otherCodeBlocks() {
        for code in ["~~~sh\ncat /tmp/report.pdf\n~~~", "    cat /tmp/report.pdf"] {
            let row = TranscriptRowText.derive(from: "[Report](/tmp/report.pdf)\n\n\(code)")
            #expect(row.prose == code)
        }
    }
}
