import Testing
@testable import LFGCore

@Suite("Outgoing attachment message assembly")
struct OutgoingAttachmentMessageTests {
    @Test("send readiness accepts text, attachments, or both, but not an empty draft")
    func sendReadiness() {
        #expect(OutgoingAttachmentMessage.canSend(text: "hello", attachmentCount: 0))
        #expect(OutgoingAttachmentMessage.canSend(text: "", attachmentCount: 1))
        #expect(OutgoingAttachmentMessage.canSend(text: "hello", attachmentCount: 1))
        #expect(!OutgoingAttachmentMessage.canSend(text: " \n ", attachmentCount: 0))
    }

    @Test("attachment-only messages contain every uploaded path")
    func attachmentOnly() throws {
        let result = try OutgoingAttachmentMessage.assemble(
            text: "",
            uploadedPaths: ["/tmp/lfg-uploads/a/photo.png", "/tmp/lfg-uploads/b/report.pdf"],
            expectedAttachmentCount: 2
        )

        #expect(result == "/tmp/lfg-uploads/a/photo.png\n/tmp/lfg-uploads/b/report.pdf")
    }

    @Test("typed text and attachments form one ordered message")
    func textAndAttachments() throws {
        let result = try OutgoingAttachmentMessage.assemble(
            text: "Review these together",
            uploadedPaths: ["/tmp/lfg-uploads/a/photo.png", "/tmp/lfg-uploads/b/data.csv"],
            expectedAttachmentCount: 2
        )

        #expect(result == "Review these together\n/tmp/lfg-uploads/a/photo.png\n/tmp/lfg-uploads/b/data.csv")
    }

    @Test("text-only messages are unchanged apart from surrounding whitespace")
    func textOnly() throws {
        let result = try OutgoingAttachmentMessage.assemble(
            text: "  keep text-only sends working \n",
            uploadedPaths: [],
            expectedAttachmentCount: 0
        )

        #expect(result == "keep text-only sends working")
    }

    @Test("a missing upload fails instead of silently degrading the message")
    func missingUpload() {
        #expect(throws: OutgoingAttachmentMessage.Error.missingUploads(expected: 2, actual: 1)) {
            try OutgoingAttachmentMessage.assemble(
                text: "Do not send just this text",
                uploadedPaths: ["/tmp/lfg-uploads/a/photo.png"],
                expectedAttachmentCount: 2
            )
        }
    }

    @Test("an entirely empty message is rejected")
    func emptyMessage() {
        #expect(throws: OutgoingAttachmentMessage.Error.emptyMessage) {
            try OutgoingAttachmentMessage.assemble(
                text: " \n ",
                uploadedPaths: [],
                expectedAttachmentCount: 0
            )
        }
    }
}
