import Foundation
import Testing

@testable import LFGCore

@Suite("TaskDirectoryGrouping")
struct TaskDirectoryGroupingTests {
    private func task(_ id: String, cwd: String) throws -> ScheduledTaskRecord {
        let json = #"{"id":"\#(id)","name":"t \#(id)","cwd":"\#(cwd)"}"#
        return try JSONDecoder().decode(ScheduledTaskRecord.self, from: Data(json.utf8))
    }

    @Test("the folder name is the last path component; blank is a dash")
    func directoryName() throws {
        #expect(TaskDirectoryGrouping.directoryName(try task("a", cwd: "/Users/e/dev/personal/lfg")) == "lfg")
        #expect(TaskDirectoryGrouping.directoryName(try task("b", cwd: "/Users/e/inbox/s2-e2e-check/")) == "s2-e2e-check")
        #expect(TaskDirectoryGrouping.directoryName(try task("c", cwd: "")) == "—")
    }

    @Test("groups are folders A–Z, case-insensitive; items keep their order")
    func sections() throws {
        let items = [
            try task("1", cwd: "/x/noto"), try task("2", cwd: "/x/lfg"),
            try task("3", cwd: "/y/Noto"), try task("4", cwd: "/x/lfg"),
        ]
        let groups = TaskDirectoryGrouping.sections(items) { $0 }
        #expect(groups.map(\.directory) == ["lfg", "noto", "Noto"] || groups.map(\.directory) == ["lfg", "Noto", "noto"])
        #expect(groups.first { $0.directory == "lfg" }?.items.map(\.id) == ["2", "4"])
    }

    @Test("hidden directories hide a task by its folder, by the Sessions rule")
    func hidden() throws {
        let items = [try task("1", cwd: "/Users/e/.gbrain/run-1"), try task("2", cwd: "/Users/e/dev/lfg")]
        let hidden = HiddenDirs(["/Users/e/.gbrain"])
        #expect(TaskDirectoryGrouping.visible(items, hidden: hidden) { $0 }.map(\.id) == ["2"])
        #expect(TaskDirectoryGrouping.visible(items, hidden: HiddenDirs()) { $0 }.count == 2)
    }
}
