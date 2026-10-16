import Foundation
import Testing
@testable import LFGCore

@Suite("S2 queued strip: row state and menu")
struct QueuedStripRowTests {
    @Test("a message lfg still holds can be sent now, edited or removed")
    func heldByLFG() {
        let row = QueuedStripRow(failed: false, queuedOffline: false, queuedForResume: false,
                                 serverStatus: "pending", agent: "claude")
        #expect(row.icon == .spinner)
        #expect(row.tag == nil)
        #expect(row.actions == [.sendNow, .edit, .remove])
        #expect(row.menuNote == nil)
        #expect(row.accessibilityLabel == "Queued message options")
    }

    @Test("once the agent has it in its own queue only Send now is honest")
    func withAgent() {
        let claude = QueuedStripRow(failed: false, queuedOffline: false, queuedForResume: false,
                                    serverStatus: "queued", agent: "claude")
        #expect(claude.actions == [.sendNow])
        #expect(claude.menuNote == "Already with Claude")
        let codex = QueuedStripRow(failed: false, queuedOffline: false, queuedForResume: false,
                                   serverStatus: "queued", agent: "codex")
        #expect(codex.menuNote == "Already with Codex")
    }

    @Test("a send the host never got says Not sent and offers Retry, Edit, Delete")
    func failed() {
        let row = QueuedStripRow(failed: true, queuedOffline: false, queuedForResume: false,
                                 serverStatus: nil, agent: "claude")
        #expect(row.icon == .failed)
        #expect(row.tag == "Not sent")
        #expect(row.tagIsError)
        #expect(row.actions == [.retry, .edit, .delete])
        #expect(row.accessibilityLabel == "Message not sent. Options")
    }

    @Test("held on the phone while the host is offline: a clock and Queued")
    func offline() {
        let row = QueuedStripRow(failed: false, queuedOffline: true, queuedForResume: false,
                                 serverStatus: nil, agent: "claude")
        #expect(row.icon == .clock)
        #expect(row.tag == "Queued")
        #expect(!row.tagIsError)
        #expect(row.actions == [.trySendingNow, .edit, .remove])
    }

    @Test("a resume kickoff is not a server queue entry, so only removal is offered")
    func resume() {
        let row = QueuedStripRow(failed: false, queuedOffline: false, queuedForResume: true,
                                 serverStatus: nil, agent: "claude")
        #expect(row.icon == .spinner)
        #expect(row.tag == "Queued")
        #expect(row.actions == [.remove])
    }

    @Test("action titles match the boards")
    func titles() {
        #expect(QueuedStripRow.Action.sendNow.title == "Send now")
        #expect(QueuedStripRow.Action.sendNow.subtitle == "Stops the current step first")
        #expect(QueuedStripRow.Action.trySendingNow.title == "Try sending now")
        #expect(QueuedStripRow.Action.retry.title == "Retry")
        #expect(QueuedStripRow.Action.delete.isDestructive)
        #expect(QueuedStripRow.Action.remove.isDestructive)
        #expect(!QueuedStripRow.Action.edit.isDestructive)
    }
}
