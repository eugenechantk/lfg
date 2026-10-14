import Testing
@testable import LFGCore

@Suite("SessionTitleActivity")
struct SessionTitleActivityTests {
    @Test("nothing in flight shows no activity")
    func idle() {
        #expect(SessionTitleActivity.resolve(
            modelSwitchStatus: nil, forking: false, movingHost: false, busy: false) == nil)
    }

    @Test("a fork in flight reads Forking…")
    func forking() {
        let activity = SessionTitleActivity.resolve(
            modelSwitchStatus: nil, forking: true, movingHost: false, busy: false)
        #expect(activity == .forking)
        #expect(activity?.label == "Forking…")
    }

    @Test("a model switch outranks a fork")
    func modelSwitchWins() {
        let activity = SessionTitleActivity.resolve(
            modelSwitchStatus: "Switching to Codex…", forking: true, movingHost: true, busy: true)
        #expect(activity == .modelSwitch("Switching to Codex…"))
        #expect(activity?.label == "Switching to Codex…")
    }

    @Test("a fork outranks a host move and a running turn")
    func forkingOutranksMoveAndBusy() {
        #expect(SessionTitleActivity.resolve(
            modelSwitchStatus: nil, forking: true, movingHost: true, busy: true) == .forking)
        #expect(SessionTitleActivity.resolve(
            modelSwitchStatus: nil, forking: true, movingHost: false, busy: true) == .forking)
    }

    @Test("a host move outranks a running turn")
    func movingHostOutranksBusy() {
        let activity = SessionTitleActivity.resolve(
            modelSwitchStatus: nil, forking: false, movingHost: true, busy: true)
        #expect(activity == .movingHost)
        #expect(activity?.label == "Moving host…")
    }

    @Test("a running turn alone reads Running")
    func running() {
        let activity = SessionTitleActivity.resolve(
            modelSwitchStatus: nil, forking: false, movingHost: false, busy: true)
        #expect(activity == .running)
        #expect(activity?.label == "Running")
    }
}
