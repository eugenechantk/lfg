import Foundation
import Testing
@testable import LFGCore

@Suite("File pane policy")
struct FilePaneTests {
    @Test func bareHTMLFilesEnterTheSameIndexAsCards() {
        let resources = TranscriptResourceIndex.collect(from: [SessionMessage(id: "html-source", text: "/fixture/explainer.html\n/fixture/older.htm")])
        #expect(resources.files.map(\.ref.raw) == ["/fixture/explainer.html", "/fixture/older.htm"])
        #expect(resources.files.map(\.ref.kind) == [.other, .other])
        #expect(resources.files.allSatisfy { $0.messageID == "html-source" })
    }
    @Test func adaptivePresentation() {
        #expect(FilePaneLayout.presentation(width: 1194, height: 834, isPad: true, portraitDocked: false) == .side)
        #expect(FilePaneLayout.presentation(width: 834, height: 1194, isPad: true, portraitDocked: false) == .sheet)
        #expect(FilePaneLayout.presentation(width: 834, height: 1194, isPad: true, portraitDocked: true) == .top)
        #expect(FilePaneLayout.presentation(width: 599, height: 450, isPad: true, portraitDocked: true) == .sheet)
        #expect(FilePaneLayout.presentation(width: 430, height: 932, isPad: false, portraitDocked: true) == .sheet)
    }
    @Test func fullScreenIsInlineFromEveryPresentation() {
        #expect(!FilePaneLayout.isInline(isOpen: true, presentation: .sheet, fullWidth: false))
        #expect(FilePaneLayout.isInline(isOpen: true, presentation: .sheet, fullWidth: true))
        #expect(FilePaneLayout.isInline(isOpen: true, presentation: .top, fullWidth: false))
        #expect(FilePaneLayout.isInline(isOpen: true, presentation: .side, fullWidth: true))
        #expect(!FilePaneLayout.isInline(isOpen: false, presentation: .side, fullWidth: true))
    }
    @Test func headerOffersFullScreenBesideTheSplit() {
        #expect(FilePaneLayout.headerControls(inSheet: true, fullWidth: false, isPortrait: true, canDock: true) == [.dock, .expand])
        #expect(FilePaneLayout.headerControls(inSheet: true, fullWidth: false, isPortrait: true, canDock: false) == [.expand])
        #expect(FilePaneLayout.headerControls(inSheet: false, fullWidth: false, isPortrait: true, canDock: false) == [.sheet, .expand])
        #expect(FilePaneLayout.headerControls(inSheet: false, fullWidth: false, isPortrait: false, canDock: false) == [.expand])
        #expect(FilePaneLayout.headerControls(inSheet: false, fullWidth: true, isPortrait: true, canDock: false) == [.collapse])
        #expect(FilePaneLayout.headerControls(inSheet: false, fullWidth: true, isPortrait: false, canDock: false) == [.collapse])
    }
    @Test func imagesRestAtTheirWholeSize() {
        // A 1206×2622 phone screenshot in a 720×740 pane: whole image, not its width.
        let whole = ImageFit.restingScale(boundsWidth: 720, boundsHeight: 740, imageWidth: 1206, imageHeight: 2622, fitsWhole: true)
        #expect(abs(whole * 2622 - 740) < 0.001)
        #expect(whole * 1206 < 720)
        let width = ImageFit.restingScale(boundsWidth: 720, boundsHeight: 740, imageWidth: 1206, imageHeight: 2622, fitsWhole: false)
        #expect(abs(width * 1206 - 720) < 0.001)
        // A wide image fits its width either way.
        let wide = ImageFit.restingScale(boundsWidth: 720, boundsHeight: 740, imageWidth: 2000, imageHeight: 1000, fitsWhole: true)
        #expect(abs(wide * 2000 - 720) < 0.001)
    }
    @Test func closingLeavesFullScreen() {
        var state = FilePaneState()
        state.open(MediaRef(raw: "/tmp/a.png", kind: .image))
        state.fullWidth = true
        state.close()
        #expect(!state.fullWidth)
    }
    @Test func sidebarCapacity() {
        #expect(!FilePaneLayout.keepsSidebar(windowWidth: 1194, sidebarWidth: 360))
        #expect(FilePaneLayout.keepsSidebar(windowWidth: 1376, sidebarWidth: 360))
    }
    @Test func snapsAndEndpoints() {
        #expect(FilePaneLayout.horizontalSnap(proposed: 250) == .close)
        #expect(FilePaneLayout.horizontalSnap(proposed: 470) == .width(420))
        #expect(FilePaneLayout.horizontalSnap(proposed: 680) == .width(720))
        #expect(FilePaneLayout.horizontalSnap(proposed: 900) == .full)
        #expect(FilePaneLayout.portraitSnap(fraction: 0.04) == .close)
        #expect(FilePaneLayout.portraitSnap(fraction: 0.5) == .fraction(0.55))
        #expect(FilePaneLayout.portraitSnap(fraction: 0.96) == .sheet)
    }
    @Test func selectionAndWidthsRoundTrip() throws {
        var state = FilePaneState()
        let image = MediaRef(raw: "/tmp/a.png", kind: .image)
        let doc = MediaRef(raw: "/tmp/a.md", kind: .markdown)
        state.open(image)
        #expect(state.width == 420)
        state.setWidth(720)
        state.open(doc)
        #expect(state.width == 720)
        state.setWidth(420)
        state.open(image)
        #expect(state.width == 720)
        let restored = try JSONDecoder().decode(FilePaneState.self, from: JSONEncoder().encode(state))
        #expect(restored == state)
        state.close()
        #expect(state.selection == image)
        #expect(!state.isOpen)
    }
    @Test func arrivalsDoNotReplaceSelection() {
        let first = TranscriptAttachment(ref: MediaRef(raw: "/tmp/a.png", kind: .image), ts: 1, messageID: "a")
        let second = TranscriptAttachment(ref: MediaRef(raw: "/tmp/b.png", kind: .image), ts: 2, messageID: "b")
        var state = FilePaneState()
        state.observe(TranscriptResources(files: [first]))
        #expect(state.unseen.isEmpty)
        state.open(first.ref)
        state.observe(TranscriptResources(files: [second, first]))
        #expect(state.selection == first.ref)
        #expect(state.unseen == [second.id])
        state.showFiles()
        #expect(state.unseen.isEmpty)
    }
    @Test func sourceAndRewriteIdentity() {
        let old = SessionMessage(id: "old", role: "assistant", kind: "text", text: "/tmp/report.md", ts: 1)
        let new = SessionMessage(id: "new", role: "assistant", kind: "text", text: "Updated /tmp/report.md", ts: 2)
        let resources = TranscriptResourceIndex.collect(from: [old, new])
        #expect(resources.files.first?.messageID == new.stableID)
        #expect(resources.files.first?.ts == 2)
    }
    @Test func rewriteEvidenceIgnoresReadsAndFailures() {
        let path = "/tmp/report.md"
        let handoff = SessionMessage(id: "handoff", text: path)
        let read = SessionMessage(id: "read", kind: "tool_use", tool: ToolCallInfo(name: "Read", target: path))
        let edit = SessionMessage(id: "edit", kind: "tool_use", toolUseId: "edit-call", tool: ToolCallInfo(name: "Edit", target: path))
        let failure = SessionMessage(id: "failure", role: "user", kind: "tool_result", toolUseId: "edit-call", isError: true)
        let baseline = FilePaneRevision.token(for: path, messages: [handoff])
        #expect(FilePaneRevision.token(for: path, messages: [handoff, read]) == baseline)
        #expect(FilePaneRevision.token(for: path, messages: [handoff, read, edit]).hasPrefix("rewrite:edit"))
        #expect(FilePaneRevision.token(for: path, messages: [handoff, edit, failure]) == baseline)
        #expect(FilePaneRevision.token(for: "/tmp/other.md", messages: [handoff, edit]) == "")
    }
    @Test func indexAcknowledgesDotButKeepsNewRows() {
        let a = TranscriptAttachment(ref: MediaRef(raw: "/tmp/a.png", kind: .image), ts: 1)
        let b = TranscriptAttachment(ref: MediaRef(raw: "/tmp/b.png", kind: .image), ts: 2)
        var state = FilePaneState()
        state.observe(TranscriptResources(files: [a]))
        state.observe(TranscriptResources(files: [a, b]))
        state.showFiles()
        #expect(state.unseen.isEmpty)
        #expect(state.newFiles == [b.id])
        state.open(b.ref)
        #expect(state.newFiles.isEmpty)
    }
    @Test func olderHistoryIsNotANewArrival() {
        let recent = TranscriptAttachment(ref: MediaRef(raw: "/tmp/recent.png", kind: .image), ts: 200)
        let old = TranscriptAttachment(ref: MediaRef(raw: "/tmp/old.png", kind: .image), ts: 100)
        var state = FilePaneState()
        state.observe(TranscriptResources(files: [recent]))
        state.observe(TranscriptResources(files: [recent, old]))
        #expect(state.unseen.isEmpty)
        #expect(state.newFiles.isEmpty)
    }
}
