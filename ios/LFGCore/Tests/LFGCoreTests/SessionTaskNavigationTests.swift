import Foundation
import Testing
@testable import LFGCore

@Suite("Open a session's task")
struct SessionTaskNavigationTests {
    @Test("the task destination uses the owning host, including duplicate task IDs")
    func owningHost() {
        let origin = TaskOrigin(id: "task-1", name: "Daily check")
        #expect(origin.hostedTaskID(hostID: "https://pro.example") == "https://pro.example:task-1")
        #expect(origin.hostedTaskID(hostID: "https://air.example") == "https://air.example:task-1")
    }

    @Test("missing or blank task and host IDs cannot produce a destination")
    func unavailableDestination() {
        #expect(TaskOrigin(id: "", name: "Task").hostedTaskID(hostID: "pro") == nil)
        #expect(TaskOrigin(id: " \n", name: "Task").hostedTaskID(hostID: "pro") == nil)
        #expect(TaskOrigin(id: "task-1", name: "Task").hostedTaskID(hostID: " ") == nil)
        let noTask: TaskOrigin? = nil
        #expect(noTask?.hostedTaskID(hostID: "pro") == nil)
    }

    @Test("a closed session retains its explicit task association when decoded")
    func archivedAssociation() throws {
        let data = Data(#"{"sessionId":"run-1","task":{"id":"task-1","name":"Daily check"},"closed":true}"#.utf8)
        let session = try JSONDecoder().decode(ResumableSession.self, from: data)
        #expect(session.task?.hostedTaskID(hostID: "air") == "air:task-1")
    }
}
