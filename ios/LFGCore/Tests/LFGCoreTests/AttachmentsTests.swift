// An attachment's filename crosses three trust boundaries — the document
// picker, the host's filesystem, and a sidecar that may outlive the app process
// — and is then pasted into the message text as a bare token. Every edge here
// is one that would either lose a user's file or let a name steer where bytes
// land.
import Testing
import Foundation
@testable import LFGCore

@Suite("Attachment filename sanitizing")
struct AttachmentNamingTests {
    @Test("keeps an ordinary name untouched")
    func passesThroughCleanNames() {
        #expect(AttachmentNaming.sanitize(filename: "report.pdf") == "report.pdf")
        #expect(AttachmentNaming.sanitize(filename: "my-notes_v2.md") == "my-notes_v2.md")
    }

    @Test("traversal cannot escape the upload directory")
    func stripsTraversal() {
        // Only the last component may survive, and it must not itself be `..`.
        #expect(AttachmentNaming.sanitize(filename: "../../etc/passwd") == "passwd.dat")
        #expect(AttachmentNaming.sanitize(filename: "/etc/shadow") == "shadow.dat")
        #expect(AttachmentNaming.sanitize(filename: "..") == "file.dat")
        #expect(AttachmentNaming.sanitize(filename: "../../../x.png") == "x.png")
        for name in ["../../etc/passwd", "/etc/shadow", "..", "a/b/c.txt"] {
            let out = AttachmentNaming.sanitize(filename: name)
            #expect(!out.contains("/"))
            #expect(!out.contains(".."))
        }
    }

    @Test("windows separators are separators too")
    func stripsBackslashPaths() {
        #expect(AttachmentNaming.sanitize(filename: #"C:\Users\e\evil.exe"#) == "evil.exe")
    }

    @Test("whitespace collapses to underscores so the path stays one token")
    func collapsesWhitespace() {
        // The stored path is appended to the message text bare; a space there
        // truncates it for the scanner and for the agent.
        #expect(AttachmentNaming.sanitize(filename: "Q3 sales report.pdf") == "Q3_sales_report.pdf")
        #expect(AttachmentNaming.sanitize(filename: "my  long   name.csv") == "my_long_name.csv")
    }

    @Test("control characters and exotica are scrubbed")
    func scrubsControlCharacters() {
        #expect(AttachmentNaming.sanitize(filename: "we\u{0000}ird\n.txt") == "we_ird.txt")
        #expect(!AttachmentNaming.sanitize(filename: "😀photo.png").contains("😀"))
        #expect(AttachmentNaming.sanitize(filename: "a;rm -rf b.txt") == "a_rm_-rf_b.txt")
    }

    @Test("a missing extension takes the fallback, never nothing")
    func suppliesExtension() {
        #expect(AttachmentNaming.sanitize(filename: "LICENSE") == "LICENSE.dat")
        #expect(AttachmentNaming.sanitize(filename: "notes", fallbackExtension: "txt") == "notes.txt")
        // A dotfile has no extension as far as the filesystem is concerned, and
        // it must not stay hidden once stored — it becomes a plainly-named file.
        #expect(AttachmentNaming.sanitize(filename: ".gitignore") == "gitignore.dat")
    }

    @Test("absurd lengths are truncated but keep the extension")
    func truncatesLongNames() {
        let long = String(repeating: "a", count: 400) + ".pdf"
        let out = AttachmentNaming.sanitize(filename: long)
        #expect(out.count <= AttachmentNaming.maxLength)
        #expect(out.hasSuffix(".pdf"))
    }

    @Test("empty and separator-only names still produce a usable name")
    func handlesEmpty() {
        #expect(AttachmentNaming.sanitize(filename: "") == "file.dat")
        #expect(AttachmentNaming.sanitize(filename: "///") == "file.dat")
        #expect(AttachmentNaming.sanitize(filename: "   ") == "file.dat")
    }

    @Test("extension case is normalised")
    func lowercasesExtension() {
        #expect(AttachmentNaming.sanitize(filename: "IMG_0042.HEIC") == "IMG_0042.heic")
    }
}

@Suite("Attachment content types")
struct AttachmentContentTypeTests {
    @Test("known extensions map to real MIME types")
    func mapsKnownTypes() {
        #expect(AttachmentNaming.contentType(forExtension: "png") == "image/png")
        #expect(AttachmentNaming.contentType(forExtension: "JPG") == "image/jpeg")
        #expect(AttachmentNaming.contentType(forExtension: "pdf") == "application/pdf")
        #expect(AttachmentNaming.contentType(forExtension: "mov") == "video/quicktime")
        #expect(AttachmentNaming.contentType(forExtension: "csv") == "text/csv")
    }

    @Test("unknown extensions are labelled honestly, not guessed")
    func fallsBackToOctetStream() {
        #expect(AttachmentNaming.contentType(forExtension: "sqlite3") == "application/octet-stream")
        #expect(AttachmentNaming.contentType(forExtension: "") == "application/octet-stream")
    }

    @Test("MIME types map back to extensions, parameters and all")
    func reverseMapping() {
        #expect(AttachmentNaming.fileExtension(forContentType: "image/png") == "png")
        #expect(AttachmentNaming.fileExtension(forContentType: "IMAGE/JPEG") == "jpg")
        #expect(AttachmentNaming.fileExtension(forContentType: "text/plain; charset=utf-8") == "txt")
        #expect(AttachmentNaming.fileExtension(forContentType: "application/x-nonsense") == nil)
    }

    @Test("kind follows the extension")
    func classifiesKind() {
        #expect(AttachmentKind.from(ext: "heic") == .image)
        #expect(AttachmentKind.from(ext: "MP4") == .video)
        #expect(AttachmentKind.from(ext: "pdf") == .file)
        #expect(AttachmentKind.from(ext: "zip") == .file)
    }
}

@Suite("Attachment metadata")
struct AttachmentMetaTests {
    @Test("raw filename infers a sanitized name, type and kind together")
    func infersFromRawName() {
        let m = AttachmentMeta(rawFilename: "../Q3 Report.PDF")
        #expect(m.filename == "Q3_Report.pdf")
        #expect(m.contentType == "application/pdf")
        #expect(m.kind == .file)
    }

    @Test("an explicit content type wins over the inferred one")
    func explicitContentTypeWins() {
        let m = AttachmentMeta(rawFilename: "clip.bin", contentType: "video/mp4")
        #expect(m.contentType == "video/mp4")
    }

    @Test("round-trips through Codable for the outbox")
    func codableRoundTrip() throws {
        let m = AttachmentMeta(rawFilename: "shot.png")
        let back = try JSONDecoder().decode(AttachmentMeta.self, from: JSONEncoder().encode(m))
        #expect(back == m)
    }
}

@Suite("Offline outbox sidecar naming")
struct OutboxAttachmentNamingTests {
    @Test("sidecar names round-trip index and filename")
    func roundTrips() {
        let name = OutboxAttachmentNaming.sidecarName(index: 3, filename: "quarterly report.pdf")
        #expect(name == "3__quarterly_report.pdf")
        let parsed = OutboxAttachmentNaming.parse(sidecarName: name)
        #expect(parsed?.index == 3)
        #expect(parsed?.meta.filename == "quarterly_report.pdf")
        #expect(parsed?.meta.contentType == "application/pdf")
    }

    @Test("a filename containing the separator still parses on the first one")
    func separatorInFilename() {
        let name = OutboxAttachmentNaming.sidecarName(index: 1, filename: "a__b.txt")
        let parsed = OutboxAttachmentNaming.parse(sidecarName: name)
        #expect(parsed?.index == 1)
        #expect(parsed?.meta.filename == "a__b.txt")
    }

    @Test("legacy <index>.png sidecars from the previous build still replay")
    func readsLegacyFormat() {
        // Messages queued offline by the shipped build are sitting on devices;
        // dropping them on upgrade would silently lose someone's send.
        let parsed = OutboxAttachmentNaming.parse(sidecarName: "0.png")
        #expect(parsed?.index == 0)
        #expect(parsed?.meta.contentType == "image/png")
        #expect(parsed?.meta.kind == .image)
    }

    @Test("ordering is numeric, not lexicographic")
    func ordersNumerically() {
        let names = ["10__k.pdf", "2__b.png", "0__a.png", "1__c.txt"]
        let ordered = OutboxAttachmentNaming.ordered(sidecarNames: names)
        #expect(ordered.map(\.index) == [0, 1, 2, 10])
        #expect(ordered.map(\.meta.filename) == ["a.png", "c.txt", "b.png", "k.pdf"])
    }

    @Test("legacy and new sidecars interleave correctly")
    func mixedFormats() {
        let ordered = OutboxAttachmentNaming.ordered(sidecarNames: ["1__b.pdf", "0.png"])
        #expect(ordered.map(\.index) == [0, 1])
        #expect(ordered.map(\.meta.contentType) == ["image/png", "application/pdf"])
    }

    @Test("junk in the sidecar directory is dropped, not replayed at random")
    func dropsUnparseable() {
        let ordered = OutboxAttachmentNaming.ordered(sidecarNames: [".DS_Store", "notanindex__x.png", "0__ok.png"])
        #expect(ordered.map(\.meta.filename) == ["ok.png"])
    }
}

@Suite("Uploaded attachments render as cards")
struct UploadedAttachmentScanTests {
    private let uploadDir = "/var/folders/cd/T/lfg-uploads/11111111-2222-3333-4444-555555555555-1786887202321-d89c3f"

    @Test("a non-media file the user attached still becomes a card")
    func nonMediaUploadIsClaimed() {
        // The bug this covers: attaching a .csv put a wall of raw path text in
        // the transcript instead of a tappable card, because bare references are
        // restricted to known media kinds.
        for name in ["metrics.csv", "data.json", "bundle.zip", "notes.rtf", "archive.tar"] {
            let refs = MediaScanner.scan("\(uploadDir)/\(name)")
            #expect(refs.count == 1, "\(name) should be claimed")
            #expect(refs.first?.filename == name)
            #expect(refs.first?.kind == .other)
        }
    }

    @Test("known media in the upload dir keeps its real kind")
    func knownKindsUnchanged() {
        #expect(MediaScanner.scan("\(uploadDir)/clip.mp4").first?.kind == .video)
        #expect(MediaScanner.scan("\(uploadDir)/shot.png").first?.kind == .image)
        #expect(MediaScanner.scan("\(uploadDir)/Q3_Sales_Report.pdf").first?.kind == .pdf)
    }

    @Test("prose mentioning a .csv OUTSIDE the upload dir is still not a card")
    func proseIsNotClaimed() {
        // This is the whole reason bare refs are restricted; the fix must not
        // turn every file path an agent mentions into an attachment card.
        #expect(MediaScanner.scan("I wrote the results to /Users/e/out/data.csv just now.").isEmpty)
        #expect(MediaScanner.scan("see src/config.json for the settings").isEmpty)
    }

    @Test("all four attachments of one send are claimed together, in order")
    func fullSendIsClaimed() {
        let text = """
        Here you go
        \(uploadDir)/VID_037398.mp4
        \(uploadDir)/IMG_7D4730.png
        \(uploadDir)/Q3_Sales_Report.pdf
        \(uploadDir)/metrics.csv
        """
        let refs = MediaScanner.scan(text)
        #expect(refs.map(\.filename) == [
            "VID_037398.mp4", "IMG_7D4730.png", "Q3_Sales_Report.pdf", "metrics.csv",
        ])
    }
}
